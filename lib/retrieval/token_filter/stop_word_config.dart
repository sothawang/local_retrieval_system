/// 区分当前是在搜通用文档（general）还是源代码（code）。因为相同的一个词（如 if/for），在普通文章里是无意义的虚词
enum RetrievalDomain {
  general,
  code,
}
/// 停词过滤与 Token 权重控制配置类，各项规则分值是多少
class StopWordConfig {
  const StopWordConfig({
    this.baseStopWordWeight = 0.15,
    this.dynamicHighFrequencyWeight = 0.10,
    this.defaultTokenWeight = 1.0,
    this.neverFilterWeight = 1.5,
    this.codeImportantWordWeight = 1.0,
    this.dynamicDfThreshold = 0.90,
  });

  /// (0.15): 静态停用词基础权重（不直接删掉，而是降权到 0.15）。
  final double baseStopWordWeight;
  /// (0.10): 在全局 90% 以上文档中都出现的“泛滥词”的降权权重。
  final double dynamicHighFrequencyWeight;
  /// (1.0): 普通标准词的基准得分权重。
  final double defaultTokenWeight;
  /// (1.5): 核心专有名词（如无障碍领域术语 WCAG/accessibility）的提权权重。
  final double neverFilterWeight;
  /// (1.0)：代码领域下关键逻辑词（if/for/null）的保护权重。
  final double codeImportantWordWeight;
  /// (0.90)：动态高频词判定阈值（出现率 ≥90% 的词触发动态降权）。
  final double dynamicDfThreshold;
}