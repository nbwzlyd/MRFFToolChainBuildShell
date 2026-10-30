#! /usr/bin/env bash
#
# Copyright (C) 2021 Matt Reach<qianlongxu@gmail.com>

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This script is based on projects below
# https://github.com/bilibili/ijkplayer

set -e

error_handler() {
    echo "An error occurred!"
    tail -n20 ${MR_BUILD_SOURCE}/ffbuild/config.log
}

trap 'error_handler' ERR

THIS_DIR=$(DIRNAME=$(dirname "$0"); cd "$DIRNAME"; pwd)
cd "$THIS_DIR"

# ffmpeg config options
source $MR_SHELL_CONFIGS_DIR/ffconfig/module-full.sh
source $MR_SHELL_CONFIGS_DIR/ffconfig/auto-detect-third-libs.sh

CFG_FLAGS=
CFG_FLAGS="$CFG_FLAGS $COMMON_FF_CFG_FLAGS"
CFG_FLAGS="$CFG_FLAGS $THIRD_CFG_FLAGS"

# fsp: 必须放在【所有标志拼装的最后】才生效。
# 源站会把 MPEG-TS 分片伪装成 PNG（PNG 假头 + 真 TS），而本构建用的是
# module-full.sh 的 --enable-demuxers（含 png_pipe），png_pipe 的探测只看 PNG 签名
# 就能拿 99 分，会抢走分片 → 用 PNG 解码器解出 1x1 RGBA 白屏。
# ijk 的 FFmpeg 构建里没有 png_pipe（strings: ijk=0 / 我们=1），Exo 更不用 FFmpeg。
# 去掉后 TS 探测（扫 188 字节周期的 0x47）自然胜出，行为与 ijk/Exo 一致。
CFG_FLAGS="$CFG_FLAGS --disable-demuxer=image_png_pipe"

# fsp: seek 时保留 302 的签名地址，不 revert 回原始 URL。
# 实测原始 URL 对远距离 Range（seek 到 12 分钟读 MKV Cues）返回 404，
# 而签名 URL 对任意 Range 都是 206；签名 15 分钟过期后 seek 会 403（后续再刷签名）。
# 用 sed 包一层 if (0 && ...) 而不是删块，避免改错行/括号。
if [ -f "${MR_BUILD_SOURCE}/libavformat/http.c" ]; then
    sed -i.bak 's/if (strcmp(s->uri, s->location))/if (0 \&\& strcmp(s->uri, s->location))/' \
        "${MR_BUILD_SOURCE}/libavformat/http.c" 2>/dev/null || true
    # 签名 15 分钟过期后 seek 会 403：seek 前先用原始 URL 发一次 0-0 探测，
    # 拿到新签名（302）再发真实 Range。python 幂等注入，避免重复。
    python3 - "${MR_BUILD_SOURCE}/libavformat/http.c" <<'PYEOF' || true
import sys
p=sys.argv[1]
s=open(p,encoding='utf-8',errors='replace').read()
if '[fsp] refresh' not in s:
    anchor='    /* we save the old context in case the seek fails */'
    inject='''    /* [fsp] refresh the signed redirect location before the seek.
       The original uri answers 302 (fresh signature); the signed location
       answers 206 for any range (far ranges on the original uri may 404). */
    if (s->uri && s->location && strcmp(s->uri, s->location) && s->seekable) {
        uint64_t saved_off = s->off;
        char *saved_loc = av_strdup(s->location);
        if (saved_loc) {
            char *orig = av_strdup(s->uri);
            if (orig) {
                av_free(s->location);
                s->location = orig;
                s->off = 0;
                s->end_off = 1;
                if (http_open_cnx(h, &options) >= 0) {
                    ffurl_closep(&s->hd);
                    av_freep(&saved_loc);
                } else {
                    av_free(s->location);
                    s->location = saved_loc;
                    saved_loc = NULL;
                }
            }
            s->off = saved_off;
            s->end_off = 0;
            av_freep(&saved_loc);
        }
    }

'''
    if anchor in s:
        s=s.replace(anchor, inject+anchor, 1)
        open(p,'w',encoding='utf-8').write(s)
PYEOF
fi

# Android 15 with 16 kb page size support
# https://developer.android.com/guide/practices/page-sizes#compile-r27
EXTRA_LDFLAGS="-Wl,-z,max-page-size=16384"
C_FLAGS="$C_FLAGS $MR_DEFAULT_CFLAGS"
LDFLAGS="$C_FLAGS $EXTRA_LDFLAGS"


echo "----------------------"
echo "[*] configure"

if [[ ! -d $MR_BUILD_SOURCE ]]; then
    echo ""
    echo "!! ERROR"
    echo "!! Can not find lib source: $MR_BUILD_SOURCE"
    echo "!! Run 'init-*.sh' first"
    echo ""
    exit 1
fi

cd $MR_BUILD_SOURCE

if [[ -f "./config.h" ]]; then
    echo 'reuse configure'
else
    echo
    echo "CC: $MR_TRIPLE_CC"
    echo "CFLAGS: $C_FLAGS"
    echo "LDFLAG:$LDFLAGS"
    echo "FF_CFG_FLAGS: $CFG_FLAGS"
    echo

    ./configure \
        $CFG_FLAGS \
        --cc=${MR_TRIPLE_CC} \
        --as=${MR_TRIPLE_CC} \
        --ld=${MR_TRIPLE_CC} \
        --ar=${MR_AR} \
        --nm=${MR_NM} \
        --strip=${MR_STRIP} \
        --ranlib=${MR_RANLIB} \
        --extra-cflags="$C_FLAGS" \
        --extra-cxxflags="$C_FLAGS" \
        --extra-ldflags="$LDFLAGS" \
        --pkg-config=${MR_PKG_CONFIG_EXECUTABLE}
fi

#----------------------
echo "----------------------"
echo "[*] compile"

# V=1
make V=1 -j$MR_HOST_NPROC >/dev/null

echo "----------------------"
echo "[*] install"

cp config.* $MR_BUILD_PREFIX
make install >/dev/null
mkdir -p $MR_BUILD_PREFIX/include/libffmpeg
cp -f config.h $MR_BUILD_PREFIX/include/libffmpeg/
[ -e config_components.h ] && cp -f config_components.h $MR_BUILD_PREFIX/include/libffmpeg/
# copy private header for ffmpeg-kit.
[ -e $MR_BUILD_SOURCE/libavutil/getenv_utf8.h ] && cp -f $MR_BUILD_SOURCE/libavutil/getenv_utf8.h $MR_BUILD_PREFIX/include/libavutil/
cp -f $MR_BUILD_SOURCE/libavutil/internal.h $MR_BUILD_PREFIX/include/libavutil/
cp -f $MR_BUILD_SOURCE/libavutil/libm.h $MR_BUILD_PREFIX/include/libavutil/
[ -e $MR_BUILD_SOURCE/libavutil/attributes_internal.h ] && cp -f $MR_BUILD_SOURCE/libavutil/attributes_internal.h $MR_BUILD_PREFIX/include/libavutil/
cp -f $MR_BUILD_SOURCE/libavcodec/mathops.h $MR_BUILD_PREFIX/include/libavcodec/

mkdir -p $MR_BUILD_PREFIX/include/libavcodec/x86/
cp -f $MR_BUILD_SOURCE/libavcodec/x86/mathops.h $MR_BUILD_PREFIX/include/libavcodec/x86/
mkdir -p $MR_BUILD_PREFIX/include/libavutil/x86/
cp -f $MR_BUILD_SOURCE/libavutil/x86/asm.h $MR_BUILD_PREFIX/include/libavutil/x86/