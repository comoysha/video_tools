#!/bin/bash

# 作用：在当前目录下，把V_DIR所有子目录名作为关键词，在SEARCH_DIR中搜索，把搜索行为保存为 savedSearch 文件保存在子目录中

# 设置变量
V_DIR="/Users/xiayue/Library/Mobile Documents/com~apple~CloudDocs/ss/video2"
SEARCH_DIR="/Users/xiayue/Library/Mobile Documents/com~apple~CloudDocs/ss/snapshot"

# 遍历 v 目录下的所有子文件夹
for folder in "$V_DIR"/*; do
    if [ -d "$folder" ]; then
        # 获取文件夹名称
        folder_name=$(basename "$folder")
        
        # 设置 saved search 保存目录为对应的子文件夹
        SAVED_SEARCHES_DIR="$folder"
        
        # 创建 saved search 文件名
        search_file="$SAVED_SEARCHES_DIR/Search for $folder_name.savedSearch"
        
        # 检查文件是否已存在
        if [ -f "$search_file" ]; then
            echo "文件已存在，跳过: $search_file"
        else
            echo "创建新的 saved search: $search_file"
            
            # 创建 saved search 的 plist 内容
            cat > "$search_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CompatibilityVersion</key>
    <integer>1</integer>
    <key>RawQuery</key>
    <string>(** = "$folder_name*"cdws)</string>
    <key>RawQueryDict</key>
    <dict>
        <key>FinderFilesOnly</key>
        <true/>
        <key>RawQuery</key>
        <string>(** = "$folder_name*"cdws)</string>
        <key>SearchScopes</key>
        <array>
            <string>$SEARCH_DIR</string>
        </array>
    </dict>
    <key>SearchCriteria</key>
    <dict>
        <key>CurrentFolderPath</key>
        <array>
            <string>$SEARCH_DIR</string>
        </array>
        <key>FXCriteriaSlices</key>
        <array>
            <dict>
                <key>criteria</key>
                <string>kMDItemTextContent</string>
                <key>displayName</key>
                <string>Contents</string>
                <key>matchType</key>
                <integer>100</integer>
                <key>value</key>
                <string>$folder_name</string>
            </dict>
        </array>
        <key>FXScopeArrayOfPaths</key>
        <array>
            <string>$SEARCH_DIR</string>
        </array>
    </dict>
    <key>FXSavedSearchTemplate</key>
    <false/>
    <key>FXSidebarVisible</key>
    <false/>
</dict>
</plist>
EOF
            
            echo "已完成: $folder_name/Search for $folder_name.savedSearch"
        fi
    fi
done

echo "所有 saved search 文件已创建/更新完成！"
echo "saved search 文件已保存到各自对应的子文件夹中，且不会显示在 Finder 侧边栏。"