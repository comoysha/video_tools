#!/bin/bash

# --- 配置 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_DIR="$SCRIPT_DIR"
CLASSIFIED_DIR="$SCRIPT_DIR/按分辨率分类"
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

# 创建分类目录（如果不存在）
if [ ! -d "$CLASSIFIED_DIR" ]; then
    mkdir -p "$CLASSIFIED_DIR"
    echo "已创建分类目录: $CLASSIFIED_DIR"
fi

echo "正在搜索视频文件..."
echo "分类目录: $CLASSIFIED_DIR"
echo ""

# 存储所有视频文件
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
echo "开始分析视频分辨率并归类..."
echo ""

# 创建临时文件来存储统计信息
STATS_FILE="/tmp/video_classification_stats_$$"
> "$STATS_FILE"

# 分析每个视频的分辨率并归类
for video_file in "${video_files[@]}"; do
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
    
    # 创建分辨率目录
    resolution_dir="$CLASSIFIED_DIR/${width}x${height}"
    if [ ! -d "$resolution_dir" ]; then
        mkdir -p "$resolution_dir"
        echo "  📁 创建目录: ${width}x${height}"
    fi
    
    # 移动文件到对应分辨率目录
    target_file="$resolution_dir/$filename"
    
    # 检查目标文件是否已存在
    if [ -f "$target_file" ]; then
        # 如果文件已存在，添加时间戳后缀
        timestamp=$(date +%Y%m%d_%H%M%S)
        name_without_ext="${filename%.*}"
        extension="${filename##*.}"
        target_file="$resolution_dir/${name_without_ext}_${timestamp}.${extension}"
        echo "  ⚠️  文件已存在，重命名为: $(basename "$target_file")"
    fi
    
    mv "$video_file" "$target_file"
    
    if [ $? -eq 0 ]; then
        echo "  ✓ 已移动到: ${width}x${height}/$(basename "$target_file")"
        
        # 记录统计信息到临时文件
        echo "${width}x${height}|$(basename "$target_file")" >> "$STATS_FILE"
    else
        echo "  ✗ 移动失败: $filename"
    fi
    echo ""
done

echo "==========================================="
echo "分类完成！统计结果:"
echo "==========================================="

# 处理统计信息
if [ -f "$STATS_FILE" ] && [ -s "$STATS_FILE" ]; then
    # 获取所有唯一的分辨率
    resolutions=($(cut -d'|' -f1 "$STATS_FILE" | sort -u))
    
    total_resolutions=${#resolutions[@]}
    total_files=$(wc -l < "$STATS_FILE")
    
    # 显示每种分辨率的统计
    for resolution in "${resolutions[@]}"; do
        # 获取该分辨率的文件列表
        files=$(grep "^$resolution|" "$STATS_FILE" | cut -d'|' -f2 | tr '\n' ', ' | sed 's/,$//')
        count=$(grep "^$resolution|" "$STATS_FILE" | wc -l)
        
        echo "📊 分辨率: $resolution"
        echo "   文件数量: $count 个"
        echo "   文件列表: $files"
        echo "   目录位置: $CLASSIFIED_DIR/$resolution/"
        echo ""
    done
    
    echo "==========================================="
    echo "📈 总计统计:"
    echo "   发现 $total_resolutions 种不同分辨率"
    echo "   成功归类 $total_files 个视频文件"
    echo "   分类目录: $CLASSIFIED_DIR"
    echo "==========================================="
    
    # 显示目录结构
    echo ""
    echo "📁 分类后的目录结构:"
    if command -v tree >/dev/null 2>&1; then
        tree "$CLASSIFIED_DIR" -L 2
    else
        echo "$CLASSIFIED_DIR/"
        for resolution in "${resolutions[@]}"; do
            count=$(grep "^$resolution|" "$STATS_FILE" | wc -l)
            echo "├── $resolution/ ($count 个文件)"
        done
    fi
else
    echo "⚠️  没有成功归类任何文件"
fi

# 清理临时文件
rm -f "$STATS_FILE"

echo ""
echo "✅ 视频分辨率归类完成！"