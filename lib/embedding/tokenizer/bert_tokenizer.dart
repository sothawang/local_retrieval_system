import 'dart:collection';

import 'package:flutter/services.dart';

import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/exceptions/embedding_exception.dart';

// 加载 vocab.txt，完成 WordPiece Tokenization
class BertTokenizer {
   BertTokenizer._();
   // 实现单例模式（Singleton Pattern），确保在整个 App 的生命周期中，BertTokenizer 只会被创建一次，并且全局共享同一个实例。
   // 因为如果不这样每次在new BertTokenizer的时候，内存中会出现多个相同的vocab.txt内容，产生内存压力，引发闪退
   // 使用单例模式可以让多个行为共用一个tokenizer，内存占比最小，效果最好
   // 不使用单例模式会触发多次I/O行为和CPU计算
   // 每次分词都要重新加载、解析文件，会导致 UI 界面出现明显的卡顿（掉帧）
   // 单例模式确保了这种“毕其功于一役”的重型初始化在整个 App 生命周期中只发生一次。后续的分词操作（tokenize）全部变成了纯粹的内存查找（$O(1)$ 复杂度），速度极快。
   // 使用单例模式后，App 可以在启动时（例如 main() 函数中）统一进行一次初始化。
   // 之后在任何地方通过 BertTokenizer.instance 调用时，都可以百分之百确定该分词器是立即可用且行为一致的，省去了在各个业务模块之间传递对象的复杂逻辑。
   static final BertTokenizer instance = BertTokenizer._();

   final Map<String, int> _vocab = HashMap();

   bool _initialized = false;
   bool get isInitialized => _initialized;

   // 把vocab.txt里的内容复制进_vocab这个map中
   Future<void> initialize() async{
     if(_initialized){
       return;
     }
     try{
       // 磁盘 I/O： 通过 rootBundle.loadString() 从安装包中读取文本文件。
       final vocabString = await rootBundle.loadString(EmbeddingConstants.bertVocabPath);
       // CPU 计算： 通过 .split('\n') 将几十万字节的字符串切碎，并循环多次执行 .trim() 和 HashMap 的插入。
       final lines = vocabString.split('\n');
       for(int i = 0; i<lines.length; i++){
         final token = lines[i].trim();
         if(token.isEmpty){
           continue;
         }
         _vocab[token] = i;
       }
       _initialized = true;
     }catch (e){
       throw EmbeddingException(
           code: EmbeddingErrorCode.vocabularyLoadFailed,
           message: 'Failed to load BERT vocabulary: $e',
       );
     }
   }
   // 把文本里的内容按照vocab.txt里的相同内容分离出来
   List<String> tokenize(String text){
     _checkInitialized();
     // 因为空格或者'\n'这样的内容都算字符，不加trim方法去掉的话isEmpty返回false
     if(text.trim().isEmpty){
       return [];
     }
     final basicTokens = _basicTokenize(text);
     return _wordPieceTokenize(basicTokens);
   }

   // 判断_vocab里是否有这个token
   bool containsToken(String token){
     return _vocab.containsKey(token);
   }

   // 将token在_vocab中表示的数字ID返回出来
   int tokenToId(String token){
     return _vocab[token] ?? _vocab[EmbeddingConstants.unkToken]!;
   }

   // 得到_vocab这个map有多少个key
   int get vocabSize => _vocab.length;

   // 返回一个不允许被修改，只允许看的_vocab内容
   Map<String, int> get vocabulary => UnmodifiableMapView(_vocab);

   // 检查一下_vocab有没有初始化成功
   void _checkInitialized(){
     if(!_initialized){
       throw const EmbeddingException(
           code: EmbeddingErrorCode.tokenizerNotInitialized,
           message: 'BertTokenizer has not been initialized.',
       );
     }
   }

   // Basic Tokenization
   //
   // - lowercase
   // - normalize whitespace
   // - split punctuation
   List<String> _basicTokenize(String text){
     // 预处理，先把内容变成符合bert-base-uncased的内容，把多个空白变成一个空白，并且去掉最外层的空白
     final normalized = text
         .toLowerCase()
         // r'...' (Raw String / 原始字符串)：在普通字符串中，反斜杠 \ 是转义字符（比如 \n 表示换行）；加上 r 后，\ 就是单纯的反斜杠字符，不需要写成 \\s+
         // \s (空白字符)：匹配任何空白字符，包括空格、制表符（Tab \t）、换行符（\n）、回车符（\r）以及换页符等。
         // + (量词：一次或多次)：表示匹配连续的一个或多个前面的字符。
         // 把字符串中所有连续的空白字符（多个空格、换行、Tab 等）合并压缩为单个空格。
         .replaceAll(RegExp(r'\s+'), ' ')
         .trim();

     final matches = RegExp(
       // 左边是把单词拿出来，右边是把符号拿出来
       // [...]（字符集）：匹配方括号内指定的任意单个字符。
       // |(or) : 优先尝试匹配左边的模式；如果左边不匹配，则尝试匹配右边的模式。
       // [^...]（否定字符集）：匹配除了方括号内字符之外的任意单个字符。
       r"[a-z0-9]+|[^\sa-z0-9]",
       caseSensitive: false,
     ).allMatches(normalized);

     return matches
         //抓取每一个RegExpMatch的内容，group(0)表示这个RegExpMatch里的全部内容
         .map((e)=>e.group(0)!)
          //判断这里抓取出来的RegExpMath是否为空
         .where((e)=>e.isNotEmpty)
          // 转换为List
         .toList();
   }
   // WordPiece Tokenization
   // 它接收由 _basicTokenize 处理后的字符串数组（例如 ["unwanted", "!"]），遍历其中的每一个词，并依次调用 _splitWordPiece 进行进一步拆分。
   // 将批量的词汇列表统一进行子词切分，并将最终切分出的所有子词打平（Flatten）整合到一个扁平的数组 List<String> 中返回。
   List<String> _wordPieceTokenize(List<String> tokens){
     final output = <String>[];
     for(final token in tokens){
       output.addAll(_splitWordPiece(token));
     }
     return output;
   }
   // 针对单个词实现具体的 WordPiece 贪婪最长匹配算法（Greedy Longest-Match-First）。
   // 目的是为了将vocab里没法直接找到的对应内容切分让其能够找到
   // input: token = "unwanted"
   // output: ["un", "##want", "##ed"]
   List<String> _splitWordPiece(String token){
     if(_vocab.containsKey(token)){
       return [token];
     }
     final pieces = <String>[];
     // 从词的开头（start = 0）开始，尝试匹配尽可能长的子串。
     int start = 0;
     while(start<token.length){
       int end = token.length;
       String? currentPiece;
       while(start<end){
         String subToken = token.substring(start,end);
         // 子词前缀标记 ##：算法规定，如果一个子词不是词的开头（即 start > 0），
         // 必须在其前面加上 ## 前缀（例如 ##want、##ed），用来表示“这个片段是拼接在前一个片段后面的”。
         if(start>0){
           subToken = '##$subToken';
         }
         // 逐字符缩短尝试：如果 "unwanted" 不在词表中，就去掉最后一个字母尝试 "unwante"，以此类推，直到找到词表中存在的子串（例如找到 "un"）。
         if(_vocab.containsKey(subToken)){
           currentPiece = subToken;
           break;
         }
         end--;
       }
       if(currentPiece == null){
         return [EmbeddingConstants.unkToken];
       }
       pieces.add(currentPiece);
       start = end;
     }
     return pieces;
   }
}
