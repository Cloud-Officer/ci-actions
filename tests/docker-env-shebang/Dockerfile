FROM ubuntu:26.04

# Regression for #372: uutils env rejects a mismatched argv[0] under BuildKit's built-in QEMU.
RUN printf '#!/usr/bin/env sh\necho env-shebang-ok\n' > /usr/local/bin/env-shebang-probe \
    && chmod +x /usr/local/bin/env-shebang-probe \
    && env-shebang-probe

USER 65534:65534

HEALTHCHECK NONE

CMD ["true"]
