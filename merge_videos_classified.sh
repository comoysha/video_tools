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

# 生成两个随机码
RANDOM_CODE_LANDSCAPE=$(generate_random_code)
RANDOM_CODE_PORTRAIT=$(generate_random_code)

# 确保两个随机码不同
while [ "$RANDOM_CODE_LANDSCAPE" = "$RANDOM_CODE_PORTRAIT" ]; do
    RANDOM_CODE_PORTRAIT=$(generate_random_code)
done

OUTPUT_FILENAME_LANDSCAPE="merged_landscape_${RANDOM_CODE_LANDSCAPE}.mp4"
OUTPUT_FILENAME_PORTRAIT="merged_portrait_${RANDOM_CODE_PORTRAIT}.mp4"

# 横屏分辨率：1920x1088
LANDSCAPE_WIDTH=1920
LANDSCAPE_HEIGHT=1088

# 竖屏分辨率：1088x1920
PORTRAIT_WIDTH=1088
PORTRAIT_HEIGHT=1920
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

# 创建临时文件列表和目录
TEMP_LIST_LANDSCAPE="$OUTPUT_DIR/landscape_list.txt"
TEMP_LIST_PORTRAIT="$OUTPUT_DIR/portrait_list.txt"
TEMP_DIR_LANDSCAPE="$OUTPUT_DIR/temp_landscape"
TEMP_DIR_PORTRAIT="$OUTPUT_DIR/temp_portrait"

# 清空临时文件列表和创建临时目录
> "$TEMP_LIST_LANDSCAPE"
> "$TEMP_LIST_PORTRAIT"
mkdir -p "$TEMP_DIR_LANDSCAPE"
mkdir -p "$TEMP_DIR_PORTRAIT"

echo "正在搜索视频文件..."
echo "横屏随机码: $RANDOM_CODE_LANDSCAPE"
echo "竖屏随机码: $RANDOM_CODE_PORTRAIT"
echo "横屏输出文件名: $OUTPUT_FILENAME_LANDSCAPE"
echo "竖屏输出文件名: $OUTPUT_FILENAME_PORTRAIT"
echo ""

# 计数器
landscape_files=()
portrait_files=()
all_video_files=()

# 查找所有视频文件
for ext in mp4 avi mov mkv flv wmv m4v; do
    while IFS= read -r -d '' video_file; do
        all_video_files+=("$video_file")
        echo "找到视频文件: $(basename "$video_file")"
    done < <(find "$VIDEO_DIR" -maxdepth 1 -type f -iname "*.$ext" -print0 | sort -z)
done

# 检查是否找到视频文件
if [ ${#all_video_files[@]} -eq 0 ]; then
    echo "错误: 在目录 '$VIDEO_DIR' 中没有找到任何视频文件。"
    echo "支持的格式: mp4, avi, mov, mkv, flv, wmv, m4v"
    exit 1
fi

echo "共找到 ${#all_video_files[@]} 个视频文件"
echo "开始分析视频分辨率并分类..."
echo ""

# 分析每个视频的分辨率并分类
for video_file in "${all_video_files[@]}"; do
    filename=$(basename "$video_file")
    echo "分析文件: $filename"
    
    # 获取视频分辨率
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video_file" 2>/dev/null)
    
    if [ -z "$resolution" ]; then
        echo "  ⚠️  无法获取分辨率，跳过此文件"
        continue
    fi
    
    width=$(echo "$resolution" | cut -d'x' -f1)
    height=$(echo "$resolution" | cut -d'x' -f2)
    
    echo "  分辨率: ${width}x${height}"
    
    # 判断横屏还是竖屏
    if [ "$width" -ge "$height" ]; then
        landscape_files+=("$video_file")
        echo "  📱 分类: 横屏"
    else
        portrait_files+=("$video_file")
        echo "  📱 分类: 竖屏"
    fi
    echo ""
done

echo "分类结果:"
echo "横屏视频: ${#landscape_files[@]} 个"
echo "竖屏视频: ${#portrait_files[@]} 个"
echo ""

# 处理横屏视频
if [ ${#landscape_files[@]} -gt 0 ]; then
    echo "=== 开始处理横屏视频 ==="
    echo "目标分辨率: ${LANDSCAPE_WIDTH}x${LANDSCAPE_HEIGHT}"
    
    for i in "${!landscape_files[@]}"; do
        input_file="${landscape_files[$i]}"
        filename=$(basename "$input_file")
        normalized_file="$TEMP_DIR_LANDSCAPE/normalized_$(printf "%03d" $((i+1)))_$filename"
        
        echo "正在处理横屏视频 ($((i+1))/${#landscape_files[@]}): $filename"
        
        # 标准化分辨率，保持宽高比，用黑边填充
        ffmpeg -i "$input_file" \
            -vf "scale=${LANDSCAPE_WIDTH}:${LANDSCAPE_HEIGHT}:force_original_aspect_ratio=decrease,pad=${LANDSCAPE_WIDTH}:${LANDSCAPE_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black" \
            -c:a copy \
            -y "$normalized_file" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "file '$normalized_file'" >> "$TEMP_LIST_LANDSCAPE"
            echo "  ✓ 标准化完成"
        else
            echo "  ✗ 标准化失败，跳过此文件"
        fi
        echo ""
    done
    
    # 合并横屏视频
    if [ -s "$TEMP_LIST_LANDSCAPE" ]; then
        echo "开始合并横屏视频..."
        ffmpeg -f concat -safe 0 -i "$TEMP_LIST_LANDSCAPE" -c copy "$OUTPUT_DIR/$OUTPUT_FILENAME_LANDSCAPE" -y 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ 横屏视频合并成功！"
            echo "输出文件: $OUTPUT_DIR/$OUTPUT_FILENAME_LANDSCAPE"
            
            # 显示输出文件信息
            echo "--- 横屏视频文件信息 ---"
            ffprobe -v quiet -show_entries format=duration,size -show_entries stream=width,height -of default=noprint_wrappers=1 "$OUTPUT_DIR/$OUTPUT_FILENAME_LANDSCAPE" 2>/dev/null
            echo ""
        else
            echo "❌ 横屏视频合并失败！"
        fi
    else
        echo "⚠️  没有成功标准化的横屏视频文件"
    fi
else
    echo "ℹ️  没有找到横屏视频文件"
fi

echo ""

# 处理竖屏视频
if [ ${#portrait_files[@]} -gt 0 ]; then
    echo "=== 开始处理竖屏视频 ==="
    echo "目标分辨率: ${PORTRAIT_WIDTH}x${PORTRAIT_HEIGHT}"
    
    for i in "${!portrait_files[@]}"; do
        input_file="${portrait_files[$i]}"
        filename=$(basename "$input_file")
        normalized_file="$TEMP_DIR_PORTRAIT/normalized_$(printf "%03d" $((i+1)))_$filename"
        
        echo "正在处理竖屏视频 ($((i+1))/${#portrait_files[@]}): $filename"
        
        # 标准化分辨率，保持宽高比，用黑边填充
        ffmpeg -i "$input_file" \
            -vf "scale=${PORTRAIT_WIDTH}:${PORTRAIT_HEIGHT}:force_original_aspect_ratio=decrease,pad=${PORTRAIT_WIDTH}:${PORTRAIT_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black" \
            -c:a copy \
            -y "$normalized_file" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "file '$normalized_file'" >> "$TEMP_LIST_PORTRAIT"
            echo "  ✓ 标准化完成"
        else
            echo "  ✗ 标准化失败，跳过此文件"
        fi
        echo ""
    done
    
    # 合并竖屏视频
    if [ -s "$TEMP_LIST_PORTRAIT" ]; then
        echo "开始合并竖屏视频..."
        ffmpeg -f concat -safe 0 -i "$TEMP_LIST_PORTRAIT" -c copy "$OUTPUT_DIR/$OUTPUT_FILENAME_PORTRAIT" -y 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ 竖屏视频合并成功！"
            echo "输出文件: $OUTPUT_DIR/$OUTPUT_FILENAME_PORTRAIT"
            
            # 显示输出文件信息
            echo "--- 竖屏视频文件信息 ---"
            ffprobe -v quiet -show_entries format=duration,size -show_entries stream=width,height -of default=noprint_wrappers=1 "$OUTPUT_DIR/$OUTPUT_FILENAME_PORTRAIT" 2>/dev/null
            echo ""
        else
            echo "❌ 竖屏视频合并失败！"
        fi
    else
        echo "⚠️  没有成功标准化的竖屏视频文件"
    fi
else
    echo "ℹ️  没有找到竖屏视频文件"
fi

# 移动原始视频文件到已处理文件夹
if [ ${#all_video_files[@]} -gt 0 ] && ([ -s "$TEMP_LIST_LANDSCAPE" ] || [ -s "$TEMP_LIST_PORTRAIT" ]); then
    echo "开始移动原始视频文件到已处理文件夹..."
    for video_file in "${all_video_files[@]}"; do
        filename=$(basename "$video_file")
        echo "移动文件: $filename"
        mv "$video_file" "$PROCESSED_DIR/"
        if [ $? -eq 0 ]; then
            echo "  ✓ 已移动到: $PROCESSED_DIR/$filename"
        else
            echo "  ✗ 移动失败: $filename"
        fi
    done
    echo ""
fi

# 清理临时文件
echo "清理临时文件..."
rm -rf "$TEMP_DIR_LANDSCAPE"
rm -rf "$TEMP_DIR_PORTRAIT"
rm -f "$TEMP_LIST_LANDSCAPE"
rm -f "$TEMP_LIST_PORTRAIT"

echo "处理完成！"
if [ -s "$TEMP_LIST_LANDSCAPE" ] || [ -f "$OUTPUT_DIR/$OUTPUT_FILENAME_LANDSCAPE" ]; then
    echo "横屏合并视频: $OUTPUT_DIR/$OUTPUT_FILENAME_LANDSCAPE"
fi
if [ -s "$TEMP_LIST_PORTRAIT" ] || [ -f "$OUTPUT_DIR/$OUTPUT_FILENAME_PORTRAIT" ]; then
    echo "竖屏合并视频: $OUTPUT_DIR/$OUTPUT_FILENAME_PORTRAIT"
fi
echo "原始视频已移动到: $PROCESSED_DIR"