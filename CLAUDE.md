# 项目规范

## 日志打印规范

日志打印必须使用 `LogService` 的对应方法，通过 `category` 参数区分模块：

```
LogService.info('━━━ LLM 请求 ━━━', category: 'llm');

```

可用 category 值：`system`、`weixin`、`llm`
