# vps_sysops 与 luck-agent 集成边界

本文说明 `vps_sysops` 与 `luck-agent` 的职责边界。两个项目保持独立
开发、独立测试、独立发布和独立部署；本文只定义集成约定，不把
`luck-agent` 的业务逻辑并入 `vps_sysops`。

## 一、项目定位

### vps_sysops

`vps_sysops` 是 VPS 基础设施运维项目，面向 GCP、Azure、AWS 等主机，负责：

- 主机安全、网络、资源、磁盘和系统更新检查；
- Docker、systemd、Nginx 等基础设施服务的状态与日志检查；
- 服务部署、升级、备份、恢复和故障处理；
- 通过 host profile 描述不同云主机的差异；
- A2A bridge 等基础设施服务的部署文件、探针和运维脚本。

它是可独立使用的运维工具包，可以没有 Agent，也不依赖 LLM。

### luck-agent

`luck-agent` 是 Lark 入口和智能任务编排项目，负责：

- 接收 Lark 消息并进行权限、路由和确认；
- 将自然语言转换为受控的运维或平台操作；
- 调用 LLM、Mem0、Lark API 及其他业务服务；
- 持续维护任务、记忆、上下文和用户交互状态；
- 将运维结果格式化为适合手机端查看的消息卡片。

`luck-agent` 是 Mem0 内容的使用方。Mem0 的记忆写入、搜索和清理由
Agent 业务流程负责，不应由通用 VPS 运维脚本隐式写入。

## 二、当前部署关系

典型主机上的目录关系如下：

```text
/opt/vps_sysops/     # 独立 Git 项目：主机和服务运维
/opt/luck-agent/     # 独立 Git 项目：Lark Agent
/opt/mem0/           # 独立服务：Mem0 Server、Dashboard、PostgreSQL
```

`luck-agent` 可以通过适配器调用 `/opt/vps_sysops` 中的固定运维脚本，
但不会复制其代码，也不会把它作为 Git submodule 嵌入自己的仓库。

## 三、集成原则

### 1. vps_sysops 独立演进

- vps_sysops 的功能、脚本、profile、测试和部署在本项目中完成；
- 变更通过本项目自己的 Git 分支、commit 和部署流程发布；
- luck-agent 只依赖已发布的脚本行为或明确的机器可读接口；
- 不在 luck-agent 仓库中维护 vps_sysops 的副本。

### 2. Agent 只能调用受控能力

Agent 不得把用户输入直接拼接为 Shell 命令。集成层必须使用固定的
操作 allowlist，例如：

```text
status
resources
services
logs
```

涉及重启、升级、删除、恢复、防火墙或其他有副作用的操作时，必须经过
明确的权限和确认流程。

### 3. 运维输出与业务内容分离

vps_sysops 可以写入日志、报告、备份和服务配置等运维数据，但不负责：

- Lark 对话记忆；
- 用户偏好和长期事实；
- Agent 任务上下文；
- Mem0 业务内容；
- 通过 LLM 自动生成并持久化的业务结论。

### 4. 优先支持免 LLM 运维

主机状态、服务健康、端口、资源、日志和 Mem0 API 连通性等确定性检查，
应当可以在没有 LLM 配额时完成。LLM 只负责理解复杂请求和编排多个动作。

## 四、服务扩展方式

未来新增服务时，先在 `vps_sysops` 中增加服务级运维能力，例如：

```text
service status
service health
service logs
service smoke
service restart
service update
```

然后由 `luck-agent` 增加薄适配层和 Lark 命令映射，例如：

```text
/service mem0 status
/service a2a health
/service new-api logs
```

推荐的演进方向是让 vps_sysops 同时提供适合人工阅读的文本输出和稳定的
JSON 输出，例如：

```bash
VPS_PROFILE=aws bash scripts/service_status.sh mem0 --format json
```

在 JSON 契约稳定前，Agent 适配器应继续使用固定脚本和严格的输出截断，
避免依赖易变的交互式菜单文本。

当前 Mem0 服务级入口为：

```text
bash scripts/mem0.sh status --format json
bash scripts/mem0.sh health --format json
bash scripts/mem0.sh logs --tail 100 --format json
bash scripts/mem0.sh smoke --format json
```

其中 `status`、`health`、`logs` 是只读能力，适合加入 Agent allowlist；
`smoke` 会写入并删除临时记忆，必须作为显式诊断动作，并经过权限确认。
上述入口检查 Mem0 服务，不承载用户画像、任务、对话上下文等业务记忆。

## 五、职责判断表

| 问题 | 归属 |
| --- | --- |
| Docker/systemd 服务是否运行 | vps_sysops |
| VPS CPU、内存、磁盘和端口 | vps_sysops |
| A2A bridge 的部署和健康检查 | vps_sysops |
| Mem0 容器、端口和 API 可达性 | vps_sysops |
| Mem0 记忆写入和搜索语义 | luck-agent / Mem0 client |
| Lark 命令、权限和确认 | luck-agent |
| LLM 调用和免费额度容错 | luck-agent |
| 用户记忆、任务和上下文 | luck-agent |

## 六、开发与发布约定

修改 vps_sysops 时：

1. 在 `vps_sysops` 项目中开发和测试；
2. 更新对应的脚本、profile、文档和 smoke test；
3. 提交独立 commit 并部署到目标 VPS；
4. 如命令或输出契约变化，再回到 luck-agent 更新适配器；
5. 在 luck-agent 中验证 Lark 命令和免 LLM 路径。

修改 luck-agent 时：

1. 在 `luck-agent` 项目中开发和测试；
2. 只调用 vps_sysops 已发布的稳定入口；
3. 不通过通用 Shell 绕过 vps_sysops 的 allowlist；
4. 不把 Agent 的业务状态写入 vps_sysops 的运维配置。

这保证两个项目可以分别维护，也方便未来将同一套 vps_sysops 运维能力
提供给其他 Agent、定时任务或人工运维流程。
