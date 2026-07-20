# 原生管理全局 Skill，不依赖 Node.js 或 Breath 后端

Breath 使用 Swift 原生实现全局 Skill 的发现、校验与安装，不调用 `npx skills`，也不要求用户安装 Node.js。ZIP 和 GitHub 安装由本地应用直接处理；skills.sh 搜索被隔离为可替换、可独立失败的在线数据源，使其接口变化或暂时不可用时不会影响本地列表及其他安装方式，并延续 Breath 无账户、无自建后端、无遥测的产品边界。
