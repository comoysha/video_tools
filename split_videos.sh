#!/bin/bash

# --- 配置 ---
# 视频文件所在的目录（使用脚本所在目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_DIR="$SCRIPT_DIR"
# 输出目录
OUTPUT_DIR="$SCRIPT_DIR/output"
# 要切分的份数
NUM_SEGMENTS=10
# --- 结束配置 ---

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

# 使用更稳妥的 find...while read 循环来处理文件名
find "$VIDEO_DIR" -maxdepth 1 -type f -name "*.mp4" -print0 | while IFS= read -r -d $'\0' INPUT_FILE; do
    
    # 跳过已经切分过的文件
    if [[ "$INPUT_FILE" == *"_part_"* ]]; then
        continue
    fi

    echo "--- 开始处理文件: $INPUT_FILE ---"

    # 获取不带扩展名的文件名
    filename=$(basename -- "$INPUT_FILE")
    extension="${filename##*.}"
    filename_no_ext="${filename%.*}"
    
    # 输出文件的前缀
    OUTPUT_PREFIX="$OUTPUT_DIR/${filename_no_ext}_part"

    # 1. 获取视频总时长 (秒)
    total_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
    if [ -z "$total_duration" ]; then
        echo "错误: 无法获取视频 '$INPUT_FILE' 的时长。"
        continue # 继续处理下一个文件
    fi

    # 2. 计算每段的时长
    segment_duration=$(echo "$total_duration / $NUM_SEGMENTS" | bc -l)

    echo "视频总时长: ${total_duration}s"
    echo "切分成 ${NUM_SEGMENTS} 份，每份时长: ${segment_duration}s"
    echo "开始切分..."

    # 3. 循环切分视频
    for i in $(seq 1 $NUM_SEGMENTS)
    do
        start_time=$(echo "($i - 1) * $segment_duration" | bc -l)
        output_filename=$(printf "%s_%02d.%s" "$OUTPUT_PREFIX" $i "$extension")
        
        echo "正在生成 ${output_filename} (开始于 ${start_time}s)..."
        
        # 使用 ffmpeg 进行切分 (-c copy 模式，速度快无损)
        ffmpeg -i "$INPUT_FILE" -ss "$start_time" -t "$segment_duration" -c copy -y "$output_filename" > /dev/null 2>&1
    done

    echo "--- 完成处理文件: $INPUT_FILE ---"
    echo ""
done

echo "所有视频处理完成！"