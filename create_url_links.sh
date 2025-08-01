#!/bin/bash

# 设置当前目录为工作目录
V_DIR="."

# 基础 URL
BASE_URL="https://missav.ws/dm20/cn/actresses/"

echo "开始在当前目录的子文件夹中创建 URL 链接文件..."

# 遍历当前目录下的所有子文件夹
for folder in "$V_DIR"/*; do
    if [ -d "$folder" ]; then
        # 获取文件夹名称
        folder_name=$(basename "$folder")
        
        # 构建完整的 URL
        full_url="${BASE_URL}${folder_name}"
        
        # 创建 .webloc 文件路径（macOS 的 URL 链接文件格式）
        webloc_file="$folder/${folder_name}.webloc"
        
        # 检查文件是否已存在
        if [ -f "$webloc_file" ]; then
            echo "文件已存在，正在覆盖: $webloc_file"
        else
            echo "创建新的 URL 链接文件: $webloc_file"
        fi
        
        # 创建 .webloc 文件内容（plist 格式）
        cat > "$webloc_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>$full_url</string>
</dict>
</plist>
EOF
        
        echo "已完成: $folder_name/${folder_name}.webloc -> $full_url"
    fi
done

echo "所有 URL 链接文件已创建/更新完成！"
echo "双击 .webloc 文件即可在默认浏览器中打开对应的 URL。"