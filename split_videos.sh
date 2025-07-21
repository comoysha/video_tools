#!/bin/bash

# --- 配置 ---
# 视频文件所在的目录（使用脚本所在目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_DIR="$SCRIPT_DIR"
# 输出目录
OUTPUT_DIR="$SCRIPT_DIR/output"
# 已处理目录
PROCESSED_DIR="$SCRIPT_DIR/已处理"
# 目标文件大小（MB）
TARGET_SIZE_MB=150
# --- 结束配置 ---

# 检查 ffmpeg 是否安装
if ! command -v ffmpeg &> /dev/null; then
    echo "错误: 未找到 ffmpeg，请先安装 ffmpeg"
    exit 1
fi

# 检查 bc 是否安装
if ! command -v bc &> /dev/null; then
    echo "错误: 未找到 bc 计算器，请先安装 bc"
    echo "macOS 安装: brew install bc"
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

# 函数：将字节转换为MB
bytes_to_mb() {
    echo "scale=2; $1 / 1024 / 1024" | bc
}

# 函数：获取文件大小（字节）
get_file_size() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        stat -f%z "$1"
    else
        # Linux
        stat -c%s "$1"
    fi
}

echo "开始扫描视频文件..."
echo "目标分割大小: ${TARGET_SIZE_MB}MB"
echo ""

# 存储已分割的文件列表
processed_files=()

# 使用更稳妥的 find...while read 循环来处理文件名
find "$VIDEO_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.m4v" \) -print0 | while IFS= read -r -d $'\0' INPUT_FILE; do
    
    # 跳过已经切分过的文件
    if [[ "$INPUT_FILE" == *"_part_"* ]]; then
        continue
    fi

    echo "--- 开始处理文件: $(basename "$INPUT_FILE") ---"

    # 获取文件大小
    file_size_bytes=$(get_file_size "$INPUT_FILE")
    file_size_mb=$(bytes_to_mb "$file_size_bytes")
    
    echo "文件大小: ${file_size_mb}MB"
    
    # 检查文件是否小于目标大小
    if (( $(echo "$file_size_mb < $TARGET_SIZE_MB" | bc -l) )); then
        echo "文件大小小于 ${TARGET_SIZE_MB}MB，跳过分割"
        echo ""
        continue
    fi
    
    # 计算需要分割的段数
    NUM_SEGMENTS=$(echo "scale=0; ($file_size_mb + $TARGET_SIZE_MB - 1) / $TARGET_SIZE_MB" | bc)
    
    echo "计算分割段数: $NUM_SEGMENTS 段"
    echo "预计每段大小: $(echo "scale=2; $file_size_mb / $NUM_SEGMENTS" | bc)MB"

    # 获取不带扩展名的文件名
    filename=$(basename -- "$INPUT_FILE")
    extension="${filename##*.}"
    filename_no_ext="${filename%.*}"
    
    # 输出文件的前缀
    OUTPUT_PREFIX="$OUTPUT_DIR/${filename_no_ext}_part"

    # 1. 获取视频总时长 (秒)
    total_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
    if [ -z "$total_duration" ]; then
        echo "错误: 无法获取视频 '$INPUT_FILE' 的时长。"
        continue # 继续处理下一个文件
    fi

    # 2. 计算每段的时长
    segment_duration=$(echo "scale=3; $total_duration / $NUM_SEGMENTS" | bc -l)

    echo "视频总时长: ${total_duration}s"
    echo "切分成 ${NUM_SEGMENTS} 份，每份时长: ${segment_duration}s"
    echo "开始切分..."

    # 标记分割是否成功
    split_success=true

    # 3. 循环切分视频
    for i in $(seq 1 $NUM_SEGMENTS)
    do
        start_time=$(echo "scale=3; ($i - 1) * $segment_duration" | bc -l)
        output_filename=$(printf "%s_%02d.%s" "$OUTPUT_PREFIX" $i "$extension")
        
        echo "正在生成第 $i 段: $(basename "$output_filename") (开始于 ${start_time}s)..."
        
        # 使用 ffmpeg 进行切分 (-c copy 模式，速度快无损)
        if [ $i -eq $NUM_SEGMENTS ]; then
            # 最后一段，不指定时长，直接到结尾
            ffmpeg -i "$INPUT_FILE" -ss "$start_time" -c copy -y "$output_filename" > /dev/null 2>&1
        else
            ffmpeg -i "$INPUT_FILE" -ss "$start_time" -t "$segment_duration" -c copy -y "$output_filename" > /dev/null 2>&1
        fi
        
        # 检查生成的文件大小
        if [ -f "$output_filename" ]; then
            output_size_bytes=$(get_file_size "$output_filename")
            output_size_mb=$(bytes_to_mb "$output_size_bytes")
            echo "  ✓ 生成完成，大小: ${output_size_mb}MB"
        else
            echo "  ✗ 生成失败"
            split_success=false
            break
        fi
    done

    # 如果分割成功，记录文件路径
    if [ "$split_success" = true ]; then
        echo "$INPUT_FILE" >> "/tmp/processed_videos_$$"
        echo "✅ 分割完成，原文件将被移动到已处理目录"
    else
        echo "❌ 分割失败，原文件保持不变"
    fi

    echo "--- 完成处理文件: $(basename "$INPUT_FILE") ---"
    echo ""
done

# 移动已分割的原始视频文件到已处理目录
if [ -f "/tmp/processed_videos_$$" ]; then
    echo "=========================================="
    echo "开始移动已分割的原始视频文件到已处理目录..."
    echo "=========================================="
    
    while IFS= read -r processed_file; do
        if [ -f "$processed_file" ]; then
            filename=$(basename "$processed_file")
            echo "移动文件: $filename"
            mv "$processed_file" "$PROCESSED_DIR/"
            if [ $? -eq 0 ]; then
                echo "  ✓ 已移动到: $PROCESSED_DIR/$filename"
            else
                echo "  ✗ 移动失败: $filename"
            fi
        fi
    done < "/tmp/processed_videos_$$"
    
    # 清理临时文件
    rm -f "/tmp/processed_videos_$$"
    
    echo ""
    echo "已处理文件移动完成！"
else
    echo "没有文件需要移动到已处理目录。"
fi

echo ""
echo "所有视频处理完成！"
echo "分割后的文件保存在: $OUTPUT_DIR"
echo "已分割的原始文件移动到: $PROCESSED_DIR"
