# php2shell (CVE-2026-109618/109619) + eMudhra CA hotfix for RUNNING containers.
#
# Portainer: Containers > <container> > Console > /bin/bash, user root > Connect,
#            then paste this whole file in one go and check the final RESULT line.
# Host:      docker exec -i <container> bash -s < in-container.sh   (or use host-runner.sh)
#
# Safe to run more than once. Changes survive a plain container restart, but are LOST when the
# container is recreated (Beanstalk deploy, instance replacement, Portainer "recreate").
# Rebuilding the service images on the fixed base image is the durable fix.
bash <<'HOTFIX'
set -u
INI_NAME=zz-security-php2shell.ini
ROOT_CONF=mozilla/emSign_ECC_Root_CA_-_G3.crt
ROOT_FILE=/usr/share/ca-certificates/$ROOT_CONF
WARN=""

fail() { echo "RESULT: FAIL $*"; exit 1; }

echo "== php2shell / eMudhra hotfix on $(hostname)"

# --- eMudhra: distrust emSign ECC Root CA - G3 in the OS trust store ---------------------------
if [ ! -f /etc/ca-certificates.conf ]; then
  echo "CA:   no /etc/ca-certificates.conf, skipped"
elif grep -q "^!$ROOT_CONF" /etc/ca-certificates.conf; then
  echo "CA:   emSign ECC Root CA - G3 already distrusted"
elif grep -q "^$ROOT_CONF" /etc/ca-certificates.conf; then
  sed -i -e "s|^$ROOT_CONF|!&|" /etc/ca-certificates.conf \
    && update-ca-certificates --fresh >/dev/null 2>&1 \
    || fail "update-ca-certificates"
  echo "CA:   emSign ECC Root CA - G3 distrusted"
else
  echo "CA:   emSign ECC Root CA - G3 not in OS bundle, nothing to do"
fi

# --- Node: it uses its own compiled-in root store, which exec cannot change ---------------------
if command -v node >/dev/null 2>&1; then
  # Node >= 15.6 can tell us directly; older Node: look for a line of the root's PEM in the binary
  bundled=$(node -e "
    const tls = require('tls'), { X509Certificate } = require('crypto');
    if (!tls.rootCertificates || !X509Certificate) { console.log('unknown'); process.exit(0); }
    console.log(tls.rootCertificates.some((p) => new X509Certificate(p).subject.includes('emSign ECC Root CA - G3')) ? 'yes' : 'no');
  " 2>/dev/null || echo unknown)
  if [ "$bundled" = "unknown" ] && [ -f "$ROOT_FILE" ]; then
    if grep -aqF "$(sed -n 3p "$ROOT_FILE")" "$(command -v node)"; then bundled=yes; else bundled=no; fi
  fi
  case "$bundled" in
    yes) WARN="node bundles emSign ECC Root CA - G3; recreate with NODE_OPTIONS=--use-openssl-ca"
         echo "NODE: WARNING $WARN" ;;
    no)  echo "NODE: bundled root store does not contain emSign ECC Root CA - G3" ;;
    *)   WARN="could not check node's bundled root store"
         echo "NODE: WARNING $WARN" ;;
  esac
fi

# --- PHP: disable session upload progress -----------------------------------------------------
if command -v php >/dev/null 2>&1 && command -v apache2ctl >/dev/null 2>&1; then
  # Official php images: one scan dir. Debian/Ubuntu packages: a separate conf.d per SAPI.
  scan_dirs=$(php --ini | sed -n 's/^Scan for additional .ini files in: *//p')
  for d in /etc/php/*/apache2/conf.d /etc/php/*/fpm/conf.d; do [ -d "$d" ] && scan_dirs="$scan_dirs $d"; done
  written=0
  for scan_dir in $scan_dirs; do
    [ -d "$scan_dir" ] || continue
    cat > "$scan_dir/$INI_NAME" <<'INI'
; php2shell (CVE-2026-109618 / CVE-2026-109619) mitigation, installed by hotfix.
; PHP 7.4 is EOL and will not receive an upstream fix.
session.upload_progress.enabled = Off
session.upload_progress.name = "7522b2a36608c57f7a9a0bcbd9e7ff4d"
INI
    echo "PHP:  wrote $scan_dir/$INI_NAME"
    written=1
  done
  [ "$written" = 1 ] || fail "no PHP ini scan dir found"

  cli=$(php -r 'echo ini_get("session.upload_progress.enabled");')
  [ -z "$cli" ] || [ "$cli" = "0" ] || fail "CLI still reports upload_progress.enabled='$cli'"

  apache2ctl -t >/dev/null 2>&1 || fail "apache2ctl -t (config test) failed"
  apache2ctl -k graceful || fail "apache graceful restart failed"
  echo "PHP:  apache gracefully restarted"

  # Verify through Apache/mod_php, not just the CLI
  docroot=${APACHE_DOCUMENT_ROOT:-}
  if [ -z "$docroot" ]; then
    docroot=$(grep -hoE '^\s*DocumentRoot\s+\S+' /etc/apache2/sites-enabled/* 2>/dev/null | awk '{print $2}' | tr -d '"' | grep -v '\$' | head -1)
  fi
  [ -d "${docroot:-}" ] || docroot=/var/www/html
  probe_name="hotfix-check-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n').php"
  echo '<?php echo "upload_progress=[", ini_get("session.upload_progress.enabled"), "]";' > "$docroot/$probe_name"
  chmod 644 "$docroot/$probe_name"
  web=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if command -v curl >/dev/null 2>&1; then
      web=$(curl -s -m 5 "http://127.0.0.1/$probe_name" || true)
    else
      web=$(php -r "echo @file_get_contents('http://127.0.0.1/$probe_name');" || true)
    fi
    case "$web" in *"upload_progress=[]"*|*"upload_progress=[0]"*) break ;; esac
  done
  rm -f "$docroot/$probe_name"
  case "$web" in
    *"upload_progress=[]"*|*"upload_progress=[0]"*) echo "PHP:  verified via Apache: upload progress disabled" ;;
    *) fail "Apache did not confirm (got: $(echo "$web" | head -c 200)). Try a plain container restart and run again." ;;
  esac
else
  echo "PHP:  not a PHP/Apache container, skipped"
fi

if [ -n "$WARN" ]; then echo "RESULT: OK (warning: $WARN)"; else echo "RESULT: OK"; fi
HOTFIX
