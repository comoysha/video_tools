#!/bin/bash

# --- 配置 ---
# 视频文件所在的目录（使用脚本所在目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_DIR="$SCRIPT_DIR"
# --- 结束配置 ---

# 检查 ffprobe 是否安装
if ! command -v ffprobe &> /dev/null; then
    echo "错误: 未找到 ffprobe，请先安装 ffmpeg"
    echo "macOS: brew install ffmpeg"
    exit 1
fi

# 检查视频目录是否存在
if [ ! -d "$VIDEO_DIR" ]; then
    echo "错误: 目录 '$VIDEO_DIR' 不存在。"
    exit 1
fi

echo "正在扫描视频文件..."
echo "目录: $VIDEO_DIR"
echo ""

# 计数器
video_count=0
video_files=()

# 查找所有视频文件
for ext in mp4 avi mov mkv flv wmv m4v webm; do
    while IFS= read -r -d '' video_file; do
        video_files+=("$video_file")
        ((video_count++))
    done < <(find "$VIDEO_DIR" -maxdepth 1 -type f -iname "*.$ext" -print0 | sort -z)
done

# 检查是否找到视频文件
if [ ${#video_files[@]} -eq 0 ]; then
    echo "在目录 '$VIDEO_DIR' 中没有找到任何视频文件。"
    echo "支持的格式: mp4, avi, mov, mkv, flv, wmv, m4v, webm"
    exit 0
fi

echo "找到 ${#video_files[@]} 个视频文件"
echo "="$(printf '%.0s' {1..60})
printf "%-30s %-15s %-10s %-10s\n" "文件名" "分辨率" "时长" "大小"
echo "="$(printf '%.0s' {1..60})

# 遍历所有视频文件并获取信息
for video_file in "${video_files[@]}"; do
    filename=$(basename "$video_file")
    
    # 获取视频分辨率
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video_file" 2>/dev/null)
    
    # 获取视频时长
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    if [ -n "$duration" ]; then
        # 转换为分:秒格式
        minutes=$(echo "$duration / 60" | bc 2>/dev/null || echo "0")
        seconds=$(echo "$duration % 60" | bc 2>/dev/null || echo "0")
        duration_formatted=$(printf "%d:%02.0f" "$minutes" "$seconds")
    else
        duration_formatted="未知"
    fi
    
    # 获取文件大小
    if [ -f "$video_file" ]; then
        file_size=$(ls -lh "$video_file" | awk '{print $5}')
    else
        file_size="未知"
    fi
    
    # 处理过长的文件名
    if [ ${#filename} -gt 28 ]; then
        display_name="${filename:0:25}..."
    else
        display_name="$filename"
    fi
    
    # 检查分辨率是否获取成功
    if [ -z "$resolution" ] || [ "$resolution" = "N/A" ]; then
        resolution="获取失败"
    fi
    
    # 输出格式化信息
    printf "%-30s %-15s %-10s %-10s\n" "$display_name" "$resolution" "$duration_formatted" "$file_size"
done

echo "="$(printf '%.0s' {1..60})
echo "总计: ${#video_files[@]} 个视频文件"

# 可选：生成详细报告到文件
read -p "是否生成详细报告到文件？(y/n): " generate_report
if [[ $generate_report =~ ^[Yy]$ ]]; then
    report_file="$VIDEO_DIR/video_resolution_report_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "视频分辨率报告"
        echo "生成时间: $(date)"
        echo "目录: $VIDEO_DIR"
        echo ""
        printf "%-40s %-15s %-12s %-10s %-15s\n" "文件名" "分辨率" "时长" "大小" "完整路径"
        echo "="$(printf '%.0s' {1..100})
        
        for video_file in "${video_files[@]}"; do
            filename=$(basename "$video_file")
            resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video_file" 2>/dev/null)
            duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
            
            if [ -n "$duration" ]; then
                minutes=$(echo "$duration / 60" | bc 2>/dev/null || echo "0")
                seconds=$(echo "$duration % 60" | bc 2>/dev/null || echo "0")
                duration_formatted=$(printf "%d:%02.0f" "$minutes" "$seconds")
            else
                duration_formatted="未知"
            fi
            
            file_size=$(ls -lh "$video_file" | awk '{print $5}')
            
            if [ -z "$resolution" ]; then
                resolution="获取失败"
            fi
            
            printf "%-40s %-15s %-12s %-10s %-15s\n" "$filename" "$resolution" "$duration_formatted" "$file_size" "$video_file"
        done
        
        echo ""
        echo "总计: ${#video_files[@]} 个视频文件"
    } > "$report_file"
    
    echo "详细报告已保存到: $report_file"
fi

echo "扫描完成！"