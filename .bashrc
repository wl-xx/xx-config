# ===== alias =====
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
# 回退上一条提交，并保留修改在暂存区
alias gr='git reset --soft HEAD~1'

# ===== function =====
# 帮助命令，用于显示配置好的别名和函数
gh() {

  # ========= 帮助文本 =========
  local OUTPUT_ALL
  OUTPUT_ALL=$(
cat << 'EOF'
别名
--------------------------------------------------------------
gs    | git status                     | 显示当前git仓库状态
gc    | git commit                     | 提交 commit
gp    | git push                       | 提交到远程
gl    | git pull                       | 从远程拉取
gr    | git reset --soft HEAD~1         | 回退上一条提交并保留暂存区
--------------------------------------------------------------

函数
--------------------------------------------------------------
gi        - 拉取最新代码并重新安装依赖
gcp       - 快速提交 commit 到远程
gca       - 合并当前提交到上一条提交
gst       - 更新分支、安装依赖并启动项目
gcpick    - 批量 cherry-pick 工具
--------------------------------------------------------------

用法
--------------------------------------------------------------
gh                 查看全部
gh --alias         只看别名
gh --functions     只看函数
gh -fu             函数简要说明
gh <函数名>        查看单个函数用法
--------------------------------------------------------------
EOF
  )

  # ========= 函数帮助映射 =========
  declare -A FUNCTION_HELP
  FUNCTION_HELP["gcp"]="gcp - 快速提交 commit 到远程\n用法示例: gcp 'commit message'"
  FUNCTION_HELP["gca"]="gca - 合并当前提交到上一条提交\n用法示例: gca -p"
  FUNCTION_HELP["gst"]="gst - 更新分支、安装依赖并启动项目\n用法示例: gst dev"
  FUNCTION_HELP["gcpick"]="gcpick - 批量 cherry-pick 工具\n用法示例: gcpick V3.2.3.0 feature/login -- a1b2c3 d4e5f6"

  # ========= 参数解析 =========
  case "$1" in
    "" )
      echo "$OUTPUT_ALL"
      ;;
    --alias )
      echo "$OUTPUT_ALL" | sed -n '1,8p'
      ;;
    --functions|-f )
      if [[ "$2" == "--usage" || "$2" == "-u" ]]; then
        echo "$OUTPUT_ALL" | sed -n '10,14p'
      elif [[ -n "$2" ]]; then
        # 查看单个函数
        if [[ -n "${FUNCTION_HELP[$2]}" ]]; then
          echo -e "${FUNCTION_HELP[$2]}"
        else
          echo "❌ 未找到函数：$2"
        fi
      else
        echo "$OUTPUT_ALL" | sed -n '10,17p'
      fi
      ;;
    -fu )
      echo "$OUTPUT_ALL" | sed -n '10,14p'
      ;;
    * )
      # 支持直接查看单个函数用法
      if [[ -n "${FUNCTION_HELP[$1]}" ]]; then
        echo -e "${FUNCTION_HELP[$1]}"
      else
        echo "❌ 未知参数：$*"
      fi
      ;;
  esac
}

# 快速提交commit
gcp() {
  git add .
  git commit -m "$1"
  git push
}

# 合并当前提交到上一条提交
gca() {
  git add .
  git commit --amend
  if [[ "$1" == "--push" || "$1" == "-p" ]]; then
    echo "强制推送到远程"
    git push --force-with-lease
    return 0
  fi
}

# 安装依赖
gi() {
  git pull
  rm -rf node_modules
  ni
}

# 项目启动命令
gst() {
    git pull
    rm -rf node_modules
    ni
    # 设置启动默认值
    name=${1:-dev}
    nr "$name"
}

# cherry-pick 多条commit到指定分支并push
gcpick() {
  # ===============================
  # 1. 版本 / 分支映射
  # ===============================
  declare -A VERSION_BRANCH_MAP
  # 分支映射，用于给多个分支定义一个统一的别名，方便使用
  VERSION_BRANCH_MAP["LTS"]="main"

  # ===============================
  # 0. 帮助 / 显示版本
  # ===============================
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "gcpick - 批量 cherry-pick 工具"
    echo ""
    echo "用法:"
    echo "  gcpick <branch|version> [<branch|version> ...] -- <commit1> <commit2> ..."
    echo "  gcpick -- <commit1> <commit2> ...   # 当前分支"
    echo ""
    echo "示例:"
    echo "  gcpick V3.2.3.0 feature/login -- a1b2c3 d4e5f6"
    echo "  gcpick -- a1b2c3"
    echo ""
    echo "说明:"
    echo "  - VERSION_BRANCH_MAP 中有映射的版本会展开为对应分支"
    echo "  - 普通分支保持原样"
    echo "  - commit id 必须在 -- 后面指定"
    echo "  - 已存在或 empty commit 会自动跳过，并在最后汇总"
    echo ""
    echo "其他命令:"
    echo "  gcpick --show-versions, -sv  # 显示已定义的版本映射"
    return 0
  fi

  if [[ "$1" == "--show-versions" || "$1" == "-sv" ]]; then
    echo "=================== 已定义版本映射 ==================="
    for key in "${!VERSION_BRANCH_MAP[@]}"; do
      echo "$key : ${VERSION_BRANCH_MAP[$key]}"
    done | sort
    echo "====================================================="
    return 0
  fi

  # ===============================
  # 2. 参数解析（使用 -- 分隔）
  # ===============================
  if [[ "$*" != *" -- "* ]]; then
    echo "❌ 用法: gcpick <branch|version> [<branch|version> ...] -- <commit1> <commit2> ..."
    return 1
  fi

  branches=()
  commits=()
  targets=()

  before_sep=()
  after_sep=()
  is_commit_part=false

  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      is_commit_part=true
      continue
    fi

    if $is_commit_part; then
      after_sep+=("$arg")
    else
      before_sep+=("$arg")
    fi
  done

  commits=("${after_sep[@]}")
  targets=("${before_sep[@]}")

  if [ "${#commits[@]}" -eq 0 ]; then
    echo "❌ 必须至少指定一个 commit id"
    return 1
  fi

  # ===============================
  # 3. 展开目标分支
  # ===============================
  for t in "${targets[@]}"; do
    if [[ -n "${VERSION_BRANCH_MAP[$t]}" ]]; then
      for b in ${VERSION_BRANCH_MAP[$t]}; do
        branches+=("$b")
      done
    else
      branches+=("$t")
    fi
  done

  if [ "${#branches[@]}" -eq 0 ]; then
    branches+=("$(git branch --show-current)")
  fi

  # 去重
  branches=($(printf "%s\n" "${branches[@]}" | awk '!seen[$0]++'))

  current_branch="$(git branch --show-current)"

  # ===============================
  # 4. 初始化跳过记录
  # ===============================
  declare -A skipped_commits  # key=branch, value="commit1 commit2 ..."

  # ===============================
  # 5. 逐分支处理
  # ===============================
  for branch in "${branches[@]}"; do
    echo ""
    echo "🚀 处理分支: $branch"

    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git checkout "$branch" || { echo "❌ 切换本地分支 $branch 失败"; continue; }
    elif git ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
      git fetch origin "$branch":"$branch" || { echo "❌ 拉取远程分支 $branch 失败"; continue; }
      git checkout "$branch" || { echo "❌ 切换分支 $branch 失败"; continue; }
    else
      echo "⚠️ 分支 $branch 不存在（本地+远程），跳过"
      continue
    fi

    git pull || { echo "❌ 分支 $branch pull 失败"; continue; }

    for commit in "${commits[@]}"; do
      # 检查 commit 是否已经在分支
      if git merge-base --is-ancestor "$commit" HEAD; then
        echo "⚠️ commit $commit 已存在于 $branch，跳过"
        skipped_commits["$branch"]+="$commit "
        continue
      fi

      echo "🍒 cherry-pick $commit"
      output=$(git cherry-pick "$commit" 2>&1)
      ret=$?

      if [[ $output == *"The previous cherry-pick is now empty"* ]]; then
        echo "⚠️ commit $commit 在 $branch 已被 cherry-pick 或 empty，跳过"
        git cherry-pick --skip &>/dev/null
        skipped_commits["$branch"]+="$commit "
        continue
      fi

      if [ $ret -eq 0 ]; then
        continue
      elif [ $ret -eq 1 ]; then
        # 冲突
        echo ""
        echo "❌ 分支 $branch cherry-pick 冲突"
        echo "👉 解决冲突后执行：git cherry-pick --continue"
        echo "👉 或放弃：git cherry-pick --abort"
        return 1
      else
        echo "❌ 分支 $branch cherry-pick 失败，错误码 $ret"
        git cherry-pick --abort &>/dev/null
        skipped_commits["$branch"]+="$commit "
      fi
    done

    echo "📤 push $branch"
    git push || echo "⚠️ push $branch 失败，请手动检查"
  done

  # ===============================
  # 6. 切回原分支
  # ===============================
  git checkout "$current_branch"

  # ===============================
  # 7. 汇总跳过的 commit
  # ===============================
  echo ""
  echo "=================== 汇总：跳过的 commit ==================="
  any_skipped=false
  for branch in "${!skipped_commits[@]}"; do
    if [[ -n "${skipped_commits[$branch]}" ]]; then
      any_skipped=true
      echo "分支 $branch 跳过 commit: ${skipped_commits[$branch]}"
    fi
  done
  if ! $any_skipped; then
    echo "无跳过的 commit"
  fi
  echo "=========================================================="
  echo ""
  echo "✅ gcpick 完成"
}

# ===== PATH =====
export PATH="$HOME/bin:$PATH"

# fnm
if [ -x "$HOME/AppData/Local/Microsoft/WinGet/Links/fnm.exe" ]; then
  export PATH="$HOME/AppData/Local/Microsoft/WinGet/Links:$PATH"
elif [ -x "$HOME/AppData/Local/fnm/fnm.exe" ]; then
  export PATH="$HOME/AppData/Local/fnm:$PATH"
fi

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell bash)"
fi
