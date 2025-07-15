#!/bin/bash

# --- 配置 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_DIR="$SCRIPT_DIR"
OUTPUT_DIR="$SCRIPT_DIR/output"
PROCESSED_DIR="$SCRIPT_DIR/已处理"

# 生成6位随机码（字母+数字）- 使用多种备用方法
generate_random_code() {
    # 方法1: 使用 /dev/urandom 和 base64
    if command -v base64 >/dev/null 2>&1; then
        RANDOM_CODE=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 6)
        if [ ${#RANDOM_CODE} -eq 6 ]; then
            echo "$RANDOM_CODE"
            return
        fi
    fi
    
    # 方法2: 使用 openssl
    if command -v openssl >/dev/null 2>&1; then
        RANDOM_CODE=$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')
        if [ ${#RANDOM_CODE} -eq 6 ]; then
            echo "$RANDOM_CODE"
            return
        fi
    fi
    
    # 方法3: 使用系统时间戳和进程ID
    TIMESTAMP=$(date +%s)
    PID=$$
    RANDOM_CODE=$(echo "${TIMESTAMP}${PID}" | md5sum | tr -dc 'A-Za-z0-9' | head -c 6)
    if [ ${#RANDOM_CODE} -eq 6 ]; then
        echo "$RANDOM_CODE"
        return
    fi
    
    # 方法4: 最后的备用方案
    echo $(date +%H%M%S)
}

RANDOM_CODE=$(generate_random_code)
OUTPUT_FILENAME="merged_video_${RANDOM_CODE}.mp4"
TARGET_WIDTH=1920
TARGET_HEIGHT=1088
# --- 结束配置 ---

# 检查 ffmpeg 是否安装
if ! command -v ffmpeg &> /dev/null; then
    echo "错误: 未找到 ffmpeg，请先安装 ffmpeg"
    exit 1
fi

# 检查视频目录是否存在
if [ ! -d "$VIDEO_DIR" ]; then
    echo "错误: 目录 '$VIDEO_DIR' 不存在。"
    exit 1
fi

# 创建输出目录（如果不存在）
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
    echo "已创建输出目录: $OUTPUT_DIR"
fi

# 创建已处理目录（如果不存在）
if [ ! -d "$PROCESSED_DIR" ]; then
    mkdir -p "$PROCESSED_DIR"
    echo "已创建已处理目录: $PROCESSED_DIR"
fi

# 创建临时文件列表
TEMP_LIST="$OUTPUT_DIR/video_list.txt"
TEMP_DIR="$OUTPUT_DIR/temp_normalized"

# 清空临时文件列表和创建临时目录
> "$TEMP_LIST"
mkdir -p "$TEMP_DIR"

echo "正在搜索视频文件..."
echo "生成的随机码: $RANDOM_CODE"
echo "输出文件名: $OUTPUT_FILENAME"

# 计数器
video_files=()

# 查找所有视频文件
for ext in mp4 avi mov mkv flv wmv m4v; do
    while IFS= read -r -d '' video_file; do
        video_files+=("$video_file")
        echo "找到视频文件: $(basename "$video_file")"
    done < <(find "$VIDEO_DIR" -maxdepth 1 -type f -iname "*.$ext" -print0 | sort -z)
done

# 检查是否找到视频文件
if [ ${#video_files[@]} -eq 0 ]; then
    echo "错误: 在目录 '$VIDEO_DIR' 中没有找到任何视频文件。"
    echo "支持的格式: mp4, avi, mov, mkv, flv, wmv, m4v"
    exit 1
fi

echo "共找到 ${#video_files[@]} 个视频文件"
echo "开始标准化视频分辨率为 ${TARGET_WIDTH}x${TARGET_HEIGHT}（使用模糊背景填充）..."

# 标准化所有视频到相同分辨率
for i in "${!video_files[@]}"; do
    input_file="${video_files[$i]}"
    filename=$(basename "$input_file")
    normalized_file="$TEMP_DIR/normalized_$(printf "%03d" $((i+1)))_$filename"
    
    echo "正在处理 ($((i+1))/${#video_files[@]}): $filename"
    
    # 获取原始分辨率
    original_resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$input_file" 2>/dev/null)
    echo "  原始分辨率: $original_resolution"
    
    # 使用模糊背景填充，替代黑边填充
    ffmpeg -i "$input_file" \
        -filter_complex "[0:v]scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:force_original_aspect_ratio=increase,crop=${TARGET_WIDTH}:${TARGET_HEIGHT},boxblur=12:2[bg]; \
                         [0:v]scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:force_original_aspect_ratio=decrease[fg]; \
                         [bg][fg]overlay=(W-w)/2:(H-h)/2" \
        -c:a copy \
        -y "$normalized_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "file '$normalized_file'" >> "$TEMP_LIST"
        echo "  ✓ 标准化完成（模糊背景填充）"
    else
        echo "  ✗ 标准化失败，跳过此文件"
    fi
    echo ""
done

# 检查是否有成功标准化的文件
if [ ! -s "$TEMP_LIST" ]; then
    echo "错误: 没有成功标准化任何视频文件。"
    echo "请检查:"
    echo "1. ffmpeg 是否正确安装"
    echo "2. 视频文件是否损坏"
    echo "3. 磁盘空间是否足够"
    rm -rf "$TEMP_DIR"
    rm -f "$TEMP_LIST"
    exit 1
fi

echo "开始拼合标准化后的视频..."

# 使用 ffmpeg 拼合视频
ffmpeg -f concat -safe 0 -i "$TEMP_LIST" -c copy "$OUTPUT_DIR/$OUTPUT_FILENAME" -y

# 检查拼合是否成功
if [ $? -eq 0 ]; then
    echo "视频拼合成功！"
    echo "输出文件: $OUTPUT_DIR/$OUTPUT_FILENAME"
    
    # 显示输出文件信息
    echo ""
    echo "--- 输出文件信息 ---"
    ffprobe -v quiet -show_entries format=duration,size -show_entries stream=width,height -of default=noprint_wrappers=1 "$OUTPUT_DIR/$OUTPUT_FILENAME" 2>/dev/null
    
    # 移动原始视频文件到已处理文件夹
    echo ""
    echo "开始移动原始视频文件到已处理文件夹..."
    for video_file in "${video_files[@]}"; do
        filename=$(basename "$video_file")
        echo "移动文件: $filename"
        mv "$video_file" "$PROCESSED_DIR/"
        if [ $? -eq 0 ]; then
            echo "  ✓ 已移动到: $PROCESSED_DIR/$filename"
        else
            echo "  ✗ 移动失败: $filename"
        fi
    done
    
else
    echo "错误: 视频拼合失败！"
    exit 1
fi

# 清理临时文件
echo "清理临时文件..."
rm -rf "$TEMP_DIR"
rm -f "$TEMP_LIST"

echo "处理完成！"
echo "合并后的视频: $OUTPUT_DIR/$OUTPUT_FILENAME"
echo "原始视频已移动到: $PROCESSED_DIR"