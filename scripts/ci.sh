#!/usr/bin/env bash
# CI 的唯一命令清单 —— GitLab CI（.gitlab-ci.yml）与 GitHub Actions（.github/workflows/ci.yml）
# 都只调用本脚本。两个平台各自只负责「装工具链 + 调 scripts/ci.sh <阶段>」，
# 这样门禁的增删只改这一处，两边不会漂移。
#
# 用法：
#   bash scripts/ci.sh lint     # 门禁 3（格式）· 5 · 8 · 10 · 11 · 12 · 依赖方向，及各门禁的自检
#   bash scripts/ci.sh types    # 门禁 3（类型）：luau-lsp analyze
#   bash scripts/ci.sh build    # 门禁 1：rojo build → place.rbxlx
#   bash scripts/ci.sh test     # 门禁 2：headless 测试
#   bash scripts/ci.sh cert     # 认证线用例（与 test 分开：两条线的报告不得合并）
#   bash scripts/ci.sh all      # 依次跑以上全部
#
# 前提：rokit.toml 固定的 stylua / lune / rojo / luau-lsp 在 PATH 上。
# 任一命令非 0 退出即整体失败（AGENTS.md 硬规则 7）。

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

step() {
	echo ""
	echo "▶ $*"
	"$@"
}

lint() {
	# 格式：范围是全部组件（src/）与工具（scripts/）。
	# tests/ 暂不在范围内：其中 5 个旧文件未按 stylua 格式化，且属于认证线受控数据。
	step stylua --config-path stylua.toml --check src scripts
	# 门禁 5：P0 规约棘轮，只许下降
	step bash scripts/p0-check.sh
	# 门禁 10（I16）：认证范围不得触碰引擎/网络/非认证层，且依赖必须在范围内
	step lune run scripts/cert-scope-check.luau
	# Carbon 依赖方向（CARBON.md §3）：只许向下 · 同层走 Integration/ · L0 不碰引擎 · 不得依赖第三方
	step lune run scripts/carbon-deps-check.luau
	# 门禁 8（CARBON.md §5）：LOC 记分板。日常只报告；release 分支设 CARBON_RELEASE=1 才阻断
	if [ "${CARBON_RELEASE:-0}" = "1" ]; then
		step lune run scripts/loc-budget.luau --release
	else
		step lune run scripts/loc-budget.luau
	fi
	# 门禁 11（I18）：需求 · 代码 · 用例 的追溯；同时生成 docs/cert/TRACE.md
	step lune run scripts/cert-trace-check.luau
	# 门禁 12：认证范围 statement 覆盖
	step lune run scripts/coverage.luau
	# 门禁必须先证明自己会失败
	step lune run scripts/cert-scope-check.luau --selftest
	step lune run scripts/carbon-deps-check.luau --selftest
	step lune run scripts/loc-budget.luau --selftest
	step lune run scripts/cert-trace-check.luau --selftest
	step lune run scripts/coverage.luau --selftest
}

types() {
	step rojo sourcemap default.project.json -o sourcemap.json
	# types/globalTypes.None.d.luau 已 vendor 进仓库，这一步不需要联网。
	# scripts/ 不在分析范围内：它们是 Lune 宿主脚本，require("@lune/*") 无法被解析。
	# 目前只分析已有代码的两个组件；其余组件立项后把目录加到这一行。
	step luau-lsp analyze \
		--sourcemap=sourcemap.json \
		--definitions:@roblox=types/globalTypes.None.d.luau \
		--base-luaurc=.luaurc \
		src/ReplicatedStorage/Deuterium src/ReplicatedStorage/TritiumSQL
}

build() {
	step rojo build default.project.json -o place.rbxlx
}

test_() {
	step lune run tests/run.luau
	step lune run tests/walkthrough.luau
}

cert() {
	step lune run tests/cert/run.luau
}

case "${1:-}" in
lint) lint ;;
types) types ;;
build) build ;;
test) test_ ;;
cert) cert ;;
all)
	lint
	types
	build
	test_
	cert
	;;
*)
	echo "用法：bash scripts/ci.sh <lint|types|build|test|cert|all>" >&2
	exit 2
	;;
esac

echo ""
echo "✔ ci.sh ${1}: 通过"
