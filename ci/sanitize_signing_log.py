"""Redact signing data before build output reaches the console or artifacts.

The only argument is the temporary .p8 file path, never its contents. Fail
closed if the configured values cannot be loaded. GitHub console masking alone
does not protect the contents of files uploaded as workflow artifacts.
"""
import base64
import os
from pathlib import Path
import re
import sys


PRIVATE_BEGIN = re.compile(r'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----')
PRIVATE_END = re.compile(r'-----END (?:[A-Z0-9]+ )*PRIVATE KEY-----')
BEARER = re.compile(r'(?i)(\bauthorization\s*[:=]\s*[\"\x27]?bearer\s+)\S+')


def load_values(key_path, environment):
    identifiers = [environment.get(name, '').strip()
                   for name in ('ASC_KEY_ID', 'ASC_ISSUER_ID')]
    key = Path(key_path).read_text(encoding='utf-8').strip()
    if not all(identifiers) or not PRIVATE_BEGIN.search(key) or not PRIVATE_END.search(key):
        raise ValueError('Missing signing redaction configuration')
    body = [line.strip() for line in key.splitlines()
            if line.strip() and not line.strip().startswith('-----')]
    if not body:
        raise ValueError('Missing private key body')
    # Include fragments and common encodings, in addition to PEM block removal.
    values = identifiers + body + [''.join(body), key.replace('\n', '\\n'),
                                 base64.b64encode(key.encode()).decode(),
                                 base64.b64encode((key + '\n').encode()).decode()]
    return sorted(set(values), key=len, reverse=True)


def sanitize(source, destination, values):
    in_private_key = False
    for line in source:
        if in_private_key or PRIVATE_BEGIN.search(line):
            in_private_key = not bool(PRIVATE_END.search(line))
            destination.write('[REDACTED PRIVATE KEY]\n')
        else:
            for value in values:
                line = line.replace(value, '[REDACTED]')
            line = BEARER.sub(r'\1[REDACTED]', line)
            destination.write(line)
        destination.flush()


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError('Expected signing key path')
        values = load_values(sys.argv[1], os.environ)
    except (OSError, UnicodeError, ValueError):
        # Do not fall back to unfiltered output, or print exception data.
        print('Signing log redaction configuration unavailable.', file=sys.stderr)
        return 1
    sanitize(sys.stdin, sys.stdout, values)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
