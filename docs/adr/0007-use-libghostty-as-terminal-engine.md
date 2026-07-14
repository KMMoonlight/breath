# 使用 libghostty 作为终端引擎

Breath 使用 libghostty 实现终端解析与渲染，并通过内部终端引擎接口与 SwiftUI/AppKit 产品层隔离。libghostty 提供高性能、现代终端兼容性和原生嵌入能力；由于其嵌入 API 尚未稳定版本化，项目固定经过验证的源码版本，并把 cmux 仅作为可研究的同类集成案例，而不将其产品代码作为依赖。
