FROM swift:6.0-amazonlinux2

RUN yum update -y && \
    yum install -y llvm-devel

WORKDIR /build

COPY ./Package.* ./
RUN swift package resolve

COPY . ./
RUN swift build -c release --static-swift-stdlib

RUN chmod a+rx entrypoint.sh

ENTRYPOINT ["/build/entrypoint.sh", "/usr/bin/llvm-objdump"]


