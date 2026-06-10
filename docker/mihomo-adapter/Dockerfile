# golang:1.23-bullseye already includes gcc, git, and curl needed for CGo.
# No apt install required — avoids network failures in restrictive environments.
FROM golang:1.23-bullseye

# Explicitly set PATH so 'go' is found when the container runs bash -lc
ENV PATH="/usr/local/go/bin:${PATH}"
ENV OHOS_SDK_HOME="/opt/ohos-sdk"
ENV DEVECO_SDK_HOME="/opt/ohos-sdk"

WORKDIR /workspace

CMD ["bash", "tools/build-mihomo-adapter.sh"]
