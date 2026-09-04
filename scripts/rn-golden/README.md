# RN ↔ Flutter 等价性黄金语料

`flutter_app/test/rn_equivalence_test.dart` 断言的期望值不是手写的，而是
**真的跑 RN 版的 TypeScript** 得到的输出。这个目录就是那个生成器。

覆盖 `src/lib/dictation.ts`、`src/lib/dictionary.ts` 的全部导出函数，
以及 `src/lib/ocr.ts` 里的 `extractWordsFromOcrText`
（`ocr.ts` 顶层 import 了 expo 模块，没法直接在 node 里跑，所以只切出
`MAX_PHRASE_TOKENS` 之后那段纯函数）。

改了 RN 侧这几个文件之后，重新生成一次，再跑 Flutter 测试即可确认两版没有分叉：

```bash
bash scripts/rn-golden/generate.sh
cd flutter_app && flutter test test/rn_equivalence_test.dart
```

输出：`flutter_app/test/golden/rn_golden.json`
