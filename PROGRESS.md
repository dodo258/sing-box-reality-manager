# 进度交接（新会话第一眼看这里，保持在 40 行以内）

## 当前任务
v4 重写，方案 `docs/specs/2026-10-10-v4-rewrite.md`，2026-10-10 按主人补充修订：sing-box 全协议、Snell 单独部署、核心自动更新、快速部署流程；拆成 8 条待办见 `docs/BACKLOG.md`。

## 下一步
1. 骨架 → 2. 多节点/分流 → 3. 其余协议 → 4. Snell+ShadowTLS → 5. 自动更新 → 6. 快速部署 → 7. migrate → 8. 切换发布（等主人确认）

## 待用户决定
- 前 7 条验收后，是否正式发布 v4.0.0

## 已知问题 / 风险
- main 上的 `install.sh` 仍是 v3，现网用户靠它安装和更新，切换前不能改。
- `.github/workflows/create_release.yml` 监听 `master`，从没运行过；里面有删除旧 release 的逻辑，改触发条件前要先去掉。
