#!/bin/bash
# 交互式菜单：支持 ↑/↓ 箭头、j/k、空格/回车、数字键直跳
# bash 3.2+ 即可（自动适配 read 超时）；无 tput 时回退数字输入菜单
# Ctrl-C 中断会恢复终端（光标/颜色），不残留不可见光标
# 用法:
#   value=$(prompt_menu "标题" --default=1 \
#     "production:生产环境 (/var/www/regora, 端口 3400)" \
#     "test:测试环境 (/var/www/regora_test, 端口 3402)")
# 输出选中项的 value（冒号前）到 stdout，菜单到 stderr

prompt_menu() {
  local title="$1"
  shift
  local default_idx=1
  local options=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --default=*)
        default_idx="${1#--default=}"
        shift
        ;;
      *)
        options+=("$1")
        shift
        ;;
    esac
  done

  local count="${#options[@]}"
  if [ "$count" -eq 0 ]; then
    echo "prompt_menu: 至少需要一个选项" >&2
    return 1
  fi

  if [ "$default_idx" -lt 1 ] || [ "$default_idx" -gt "$count" ]; then
    default_idx=1
  fi

  # 单选项直接返回
  if [ "$count" -eq 1 ]; then
    echo "${options[0]%%:*}"
    return 0
  fi

  # 非 TTY（管道/CI）：返回默认项，不绘制菜单
  if [ ! -t 0 ]; then
    echo "${options[$((default_idx - 1))]%%:*}"
    return 0
  fi

  # 提取标签（冒号后部分）
  local labels=()
  local opt
  for opt in "${options[@]}"; do
    labels+=("${opt#*:}")
  done

  local sel=$default_idx

  # 选择交互模式：tput 可用 → TUI；否则经典数字菜单
  # bash 3.2 不支持小数秒超时，方向键后续字节立即可达，整数秒不产生实际延迟
  local use_tui=0
  local esc_t="0.1"
  if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    esc_t="1"
  fi
  if command -v tput >/dev/null 2>&1; then
    use_tui=1
  fi

  if [ "$use_tui" -eq 1 ]; then
    # ===== TUI 模式：箭头键 + 空格/回车 =====
    local civis cnorm clr_eol bold cyan sgr0
    civis=$(tput civis 2>/dev/null || true)
    cnorm=$(tput cnorm 2>/dev/null || true)
    clr_eol=$(tput el 2>/dev/null || true)
    bold=$(tput bold 2>/dev/null || true)
    cyan=$(tput setaf 6 2>/dev/null || true)
    sgr0=$(tput sgr0 2>/dev/null || true)

    # 标题区
    echo "" >&2
    printf '%s%s%s\n' "$bold" "$title" "$sgr0" >&2
    printf '  %s↑/↓ 或 j/k 移动 · 空格/回车确认 · 数字键直跳%s\n' "$cyan" "$sgr0" >&2
    echo "" >&2

    # 隐藏光标
    [ -n "$civis" ] && printf '%s' "$civis" >&2

    # 渲染函数：逐行输出菜单，高亮当前选中项
    _pm_render() {
      local i=1 line marker
      for opt in "${labels[@]}"; do
        line="$opt"
        if [ "$i" -eq "$sel" ]; then
          marker="❯"
          [ -n "$bold" ] && line="${bold}${cyan}${opt}${sgr0}"
        else
          marker=" "
        fi
        printf '\r%s %s %s%s\n' "$clr_eol" "$marker" "$line" "$clr_eol" >&2
        i=$((i + 1))
      done
    }

    # Ctrl-C 中断时恢复终端（光标/颜色），再 exit 终止
    # 注意：调用方 v=$(prompt_menu) 在子 shell 执行，bash 的 $$ 在子 shell 仍是父 PID，
    # 用 kill -INT $$ 会误杀父 shell 且子 shell 不退出（导致循环重绘、终端狂闪）；
    # exit 130 在子 shell 终止子 shell，父 shell 由进程组的原始 SIGINT 处理
    _pm_sigint_cleanup() {
      [ -n "$cnorm" ] && printf '%s' "$cnorm" >&2
      [ -n "$sgr0" ] && printf '%s' "$sgr0" >&2
      unset -f _pm_render _pm_sigint_cleanup
      exit 130
    }
    local _pm_prev_int
    _pm_prev_int=$(trap -p SIGINT)
    trap '_pm_sigint_cleanup' SIGINT

    _pm_render

    local key seq1 seq2
    while true; do
      IFS= read -rsn1 key </dev/tty || true
      case "$key" in
        $'\x1b')
          # 方向键转义序列：ESC [ A/B（部分终端用 ESC O A/B）
          seq1=""; seq2=""
          read -rsn1 -t "$esc_t" seq1 </dev/tty || true
          read -rsn1 -t "$esc_t" seq2 </dev/tty || true
          if [ "$seq1" = "[" ] || [ "$seq1" = "O" ]; then
            case "$seq2" in
              A) sel=$((sel - 1)); [ "$sel" -lt 1 ] && sel=1 ;;
              B) sel=$((sel + 1)); [ "$sel" -gt "$count" ] && sel=$count ;;
            esac
          fi
          ;;
        "")
          # 回车 → 确认
          break
          ;;
        " ")
          # 空格 → 确认
          break
          ;;
        j|J)
          sel=$((sel + 1)); [ "$sel" -gt "$count" ] && sel=$count
          ;;
        k|K)
          sel=$((sel - 1)); [ "$sel" -lt 1 ] && sel=1
          ;;
        [1-9])
          # 数字键直跳到对应项（仅当选项数允许）
          if [ "$key" -le "$count" ]; then
            sel=$key
          fi
          ;;
      esac
      # 上移 count 行后重绘
      printf '\033[%dA' "$count" >&2
      _pm_render
    done

    # 恢复光标、原 SIGINT trap 并清理内部函数
    [ -n "$cnorm" ] && printf '%s' "$cnorm" >&2
    eval "${_pm_prev_int:-trap - SIGINT}"
    unset -f _pm_render _pm_sigint_cleanup
    echo "" >&2
  else
    # ===== 经典数字菜单（bash 3.2 或无 tput 降级）=====
    echo "" >&2
    echo "$title" >&2
    echo "" >&2

    local i=1
    for opt in "${labels[@]}"; do
      local mark=""
      if [ "$i" -eq "$default_idx" ]; then
        mark=" (默认，直接回车)"
      fi
      echo "  ${i}) ${opt}${mark}" >&2
      i=$((i + 1))
    done

    echo "" >&2
    local choice=""
    read -r -p "请选择 [1-${count}]: " choice </dev/tty || true
    choice="${choice:-$default_idx}"

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
      echo "无效选择: '${choice}', 使用默认项 ${default_idx}" >&2
      sel="$default_idx"
    else
      sel="$choice"
    fi
  fi

  echo "${options[$((sel - 1))]%%:*}"
}

# 多选菜单：空格 toggle 选中/取消，a 全选，n 全不选，回车确认
# 选中项 value（冒号前）按顺序以逗号拼接输出到 stdout
# 用法:
#   values=$(prompt_multi_menu "部署环境" --default=1 \
#     "production:生产环境" \
#     "test:测试环境" \
#     "edge:Edge 环境")
prompt_multi_menu() {
  local title="$1"
  shift
  local default_idx=1
  local options=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --default=*)
        default_idx="${1#--default=}"
        shift
        ;;
      *)
        options+=("$1")
        shift
        ;;
    esac
  done

  local count="${#options[@]}"
  if [ "$count" -eq 0 ]; then
    echo "prompt_multi_menu: 至少需要一个选项" >&2
    return 1
  fi

  if [ "$default_idx" -lt 1 ] || [ "$default_idx" -gt "$count" ]; then
    default_idx=1
  fi

  # 提取 value（冒号前）与 label（冒号后）
  local values=() labels=() opt
  for opt in "${options[@]}"; do
    values+=("${opt%%:*}")
    labels+=("${opt#*:}")
  done

  # 单选项直接返回
  if [ "$count" -eq 1 ]; then
    echo "${values[0]}"
    return 0
  fi

  # 选中状态数组（1=选中，0=未选中），默认项预选
  local selected=() i
  for ((i = 0; i < count; i++)); do
    selected+=("0")
  done
  selected[$((default_idx - 1))]="1"

  # 非 TTY（管道/CI）：返回默认项（单值）
  if [ ! -t 0 ]; then
    echo "${values[$((default_idx - 1))]}"
    return 0
  fi

  local sel=$default_idx

  local use_tui=0
  local esc_t="0.1"
  if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    esc_t="1"
  fi
  if command -v tput >/dev/null 2>&1; then
    use_tui=1
  fi

  _pmm_join_selected() {
    local i out=""
    for ((i = 0; i < count; i++)); do
      if [ "${selected[$i]}" = "1" ]; then
        if [ -n "$out" ]; then
          out="${out},${values[$i]}"
        else
          out="${values[$i]}"
        fi
      fi
    done
    printf '%s' "$out"
  }

  if [ "$use_tui" -eq 1 ]; then
    # ===== TUI 模式：箭头键 + 空格 toggle + a/n + 回车 =====
    local civis cnorm clr_eol bold cyan green sgr0
    civis=$(tput civis 2>/dev/null || true)
    cnorm=$(tput cnorm 2>/dev/null || true)
    clr_eol=$(tput el 2>/dev/null || true)
    bold=$(tput bold 2>/dev/null || true)
    cyan=$(tput setaf 6 2>/dev/null || true)
    green=$(tput setaf 2 2>/dev/null || true)
    sgr0=$(tput sgr0 2>/dev/null || true)

    echo "" >&2
    printf '%s%s%s\n' "$bold" "$title" "$sgr0" >&2
    printf '  %s↑/↓ 或 j/k 移动 · 空格 选中/取消 · a 全选 · n 全不选 · 回车确认%s\n' "$cyan" "$sgr0" >&2
    echo "" >&2

    [ -n "$civis" ] && printf '%s' "$civis" >&2

    _pmm_render() {
      local i=1 marker box line n_selected=0
      for opt in "${labels[@]}"; do
        if [ "${selected[$((i - 1))]}" = "1" ]; then
          box="${green}${bold}✔${sgr0}"
        else
          box="○"
        fi
        line="$opt"
        if [ "$i" -eq "$sel" ]; then
          marker="❯"
          [ -n "$bold" ] && line="${bold}${cyan}${opt}${sgr0}"
        else
          marker=" "
        fi
        printf '\r%s %s %s %s%s\n' "$clr_eol" "$marker" "$box" "$line" "$clr_eol" >&2
        i=$((i + 1))
      done
      for ((i = 0; i < count; i++)); do
        [ "${selected[$i]}" = "1" ] && n_selected=$((n_selected + 1))
      done
      printf '\r%s  %s── 已选 %d 项 · 回车确认 ──%s\n' "$clr_eol" "$cyan" "$n_selected" "$sgr0" >&2
    }

    _pmm_sigint_cleanup() {
      [ -n "$cnorm" ] && printf '%s' "$cnorm" >&2
      [ -n "$sgr0" ] && printf '%s' "$sgr0" >&2
      unset -f _pmm_render _pmm_sigint_cleanup _pmm_join_selected
      exit 130
    }
    local _pmm_prev_int
    _pmm_prev_int=$(trap -p SIGINT)
    trap '_pmm_sigint_cleanup' SIGINT

    _pmm_render

    local key seq1 seq2 idx
    while true; do
      IFS= read -rsn1 key </dev/tty || true
      case "$key" in
        $'\x1b')
          seq1=""; seq2=""
          read -rsn1 -t "$esc_t" seq1 </dev/tty || true
          read -rsn1 -t "$esc_t" seq2 </dev/tty || true
          if [ "$seq1" = "[" ] || [ "$seq1" = "O" ]; then
            case "$seq2" in
              A) sel=$((sel - 1)); [ "$sel" -lt 1 ] && sel=1 ;;
              B) sel=$((sel + 1)); [ "$sel" -gt "$count" ] && sel=$count ;;
            esac
          fi
          ;;
        "")
          # 回车 → 确认（至少选中一项）
          [ -n "$(_pmm_join_selected)" ] && break
          ;;
        " ")
          # 空格 → toggle 当前项
          idx=$((sel - 1))
          if [ "${selected[$idx]}" = "1" ]; then
            selected[$idx]="0"
          else
            selected[$idx]="1"
          fi
          ;;
        a|A)
          for ((i = 0; i < count; i++)); do selected[$i]="1"; done
          ;;
        n|N)
          for ((i = 0; i < count; i++)); do selected[$i]="0"; done
          ;;
        j|J)
          sel=$((sel + 1)); [ "$sel" -gt "$count" ] && sel=$count
          ;;
        k|K)
          sel=$((sel - 1)); [ "$sel" -lt 1 ] && sel=1
          ;;
        [1-9])
          if [ "$key" -le "$count" ]; then
            sel=$key
          fi
          ;;
      esac
      # 上移 count+1 行后重绘（count 行菜单 + 1 行状态）
      printf '\033[%dA' "$((count + 1))" >&2
      _pmm_render
    done

    [ -n "$cnorm" ] && printf '%s' "$cnorm" >&2
    eval "${_pmm_prev_int:-trap - SIGINT}"
    unset -f _pmm_render _pmm_sigint_cleanup
    echo "" >&2
  else
    # ===== 经典数字菜单（bash 3.2 或无 tput 降级，多选）=====
    echo "" >&2
    echo "$title" >&2
    echo "" >&2

    local i=1
    for opt in "${labels[@]}"; do
      local mark=""
      if [ "${selected[$((i - 1))]}" = "1" ]; then
        mark=" [*]"
      fi
      echo "  ${i}) ${opt}${mark}" >&2
      i=$((i + 1))
    done

    echo "" >&2
    local choice=""
    read -r -p "请选择（逗号分隔多个，直接回车用默认）: " choice </dev/tty || true

    if [ -n "$choice" ]; then
      local -a picks=() p
      IFS=',' read -ra picks <<<"$choice"
      # 重置默认选择，按输入重新勾选
      for ((i = 0; i < count; i++)); do selected[$i]="0"; done
      for p in "${picks[@]}"; do
        p="${p// /}"
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "$count" ]; then
          selected[$((p - 1))]="1"
        fi
      done
      # 输入无效导致全空时回退默认
      [ -z "$(_pmm_join_selected)" ] && selected[$((default_idx - 1))]="1"
    fi
  fi

  echo "$(_pmm_join_selected)"
  unset -f _pmm_join_selected 2>/dev/null || true
}

# 直接执行时自测
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  prompt_menu "示例菜单（单选）" --default=1 \
    "a:选项 A" \
    "b:选项 B" \
    "c:选项 C"
  echo "---"
  prompt_multi_menu "示例菜单（多选）" --default=1 \
    "production:生产环境" \
    "test:测试环境" \
    "edge:Edge 环境"
fi
