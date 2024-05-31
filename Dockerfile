# This image is built with arch: amd64 flavor: lxde image: ubuntu:20.04

################################################################################
# base system
# nvidia image with vulkan sdk and cuda drivers installed
################################################################################
FROM nvidia/vulkan:1.3-470 as system

# basic built-in packages
ENV DEBIAN_FRONTEND noninteractive
RUN apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/3bf863cc.pub \
    && apt-get update \
    && apt install -y software-properties-common curl apache2-utils

# install utils 
RUN echo "Updates" \
    && apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing supervisor \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing nginx \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing sudo \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing net-tools \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing zenity \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing xz-utils \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing dbus-x11 \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing x11-utils \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing alsa-utils \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing mesa-utils \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing libgl1-mesa-dri

# cleaning up any residual packages
RUN echo "Cleanup" \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# install debs error if combine together
RUN apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated \
        xvfb x11vnc \
        vim-tiny firefox ttf-ubuntu-font-family ttf-wqy-zenhei  \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# installing google chrome stable version
RUN apt update \
    && apt install -y gpg-agent --fix-missing \
    && curl -LO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && (dpkg -i ./google-chrome-stable_current_amd64.deb || apt-get install -fy) \
    && curl -sSL https://dl.google.com/linux/linux_signing_key.pub | apt-key add \
    && rm google-chrome-stable_current_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# installing standard display themes
RUN apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing lxde \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing gtk2-engines-murrine \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing gnome-themes-standard \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing gtk2-engines-pixbuf \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing gtk2-engines-murrine \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing arc-theme \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Additional(optional) packages require ~600MB 
# libreoffice pinta language-pack-zh-hant language-pack-gnome-zh-hant firefox-locale-zh-hant libreoffice-l10n-zh-tw

# tini to fix subreap
ARG TINI_VERSION=v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /bin/tini
RUN chmod +x /bin/tini

# ffmpeg for handling video, audio, and other multimedia files and streams.
RUN apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated --fix-missing ffmpeg  \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /usr/local/ffmpeg \
    && ln -s /usr/bin/ffmpeg /usr/local/ffmpeg/ffmpeg

# installing python library
COPY requirements.vdt.txt /tmp/
RUN apt-get update \
    && dpkg-query -W -f='${Package}\n' > /tmp/a.txt \
    && apt-get install -y python3-pip python3-dev build-essential \
	&& pip3 install setuptools wheel && pip3 install -r /tmp/requirements.vdt.txt \
    && ln -s /usr/bin/python3 /usr/local/bin/python \
    && dpkg-query -W -f='${Package}\n' > /tmp/b.txt \
    && apt-get remove -y `diff --changed-group-format='%>' --unchanged-group-format='' /tmp/a.txt /tmp/b.txt | xargs` \
    && apt-get autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* /tmp/a.txt /tmp/b.txt


################################################################################
# builder
################################################################################
FROM ubuntu:20.04 as builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends --fix-missing ca-certificates curl gnupg patch 

# nodejs server to serve the display
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash - \
    && apt-get install -y nodejs

# yarn to install packages
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y yarn

# build frontend to serve the display
COPY web /src/web
RUN cd /src/web \
    && yarn \
    && yarn build
RUN sed -i 's#app/locale/#novnc/app/locale/#' /src/web/dist/static/novnc/app/ui.js

################################################################################
# merge builder and base system
################################################################################
FROM system
LABEL maintainer="farrukh.shahid0@gmail.com"

COPY --from=builder /src/web/dist/ /usr/local/lib/web/frontend/
COPY rootfs /
RUN ln -sf /usr/local/lib/web/frontend/static/websockify /usr/local/lib/web/frontend/static/novnc/utils/websockify && \
	chmod +x /usr/local/lib/web/frontend/static/websockify/run

EXPOSE 80
WORKDIR /root
ENV HOME=/home/ubuntu \
    SHELL=/bin/bash
HEALTHCHECK --interval=30s --timeout=5s CMD curl --fail http://127.0.0.1:6079/api/health
ENTRYPOINT ["/startup.sh"]
