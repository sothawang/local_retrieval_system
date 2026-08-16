import 'dart:async';
import 'dart:collection';

import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';

/// Singleton inference queue.
///
/// Limits the maximum number of concurrent inference tasks.
/// All model inference (BERT / MobileCLIP) should be executed
/// through this queue.
// 外部代码不断调用 enqueue() 提交任务（生产者）
//      ↓
// 任务先进入队列排队
//      ↓
// _processQueue() 按"最多2个同时跑"的规则，从队列里取任务执行（消费者）
//      ↓
// 一个任务跑完，腾出空位，自动尝试再取下一个
// 单例推理队列，并发限制 ≤2
class InferenceQueue {
  // 饿汉式单例模式启动
  InferenceQueue._();
  // 全局唯一的静态实例，整个App共享同一个队列。
  // 如果每次调用推理时都 new 一个新的 InferenceQueue，那"最多2个并发"这个限制就形同虚设了——因为每个队列各自独立计数，
  // 10个不同的队列实例依然可以同时跑20个任务。必须全局共用同一份计数器，限流才有意义。
  static final InferenceQueue instance = InferenceQueue._();

  // 一个队列（先进先出，FIFO），存放还没轮到执行的任务。
  final Queue<_InferenceTask<dynamic>> _queue = Queue();
  // 一个队列中最大任务数
  final int _maxConcurrency = EmbeddingConstants.maxConcurrentInference;
  // 当前正在跑的任务数量的计数器。
  int _runningTasks = 0;

  // Add a task into inference queue.
  Future<T> enqueue<T>(Future<T> Function() task){
    final completer = Completer<T>();
    // 把任务和它的"空头支票"打包，塞进队列排队
    _queue.add(_InferenceTask<T>(
      task: task,
      completer: completer,
    ));
    // 尝试触发一次调度（看看现在有没有空位可以立刻执行）
    _processQueue();
    // 立刻把这张"空头支票"还给调用者
    return completer.future;
  }

  // 检查队列里是否还有任务未完成，同时检查并行任务数是否<=2
  void _processQueue(){
    // 当前正在跑的任务数 小于 最大并发限制（还有空位）
    // 队列里 还有 排队的任务（有活可干）
    while(_runningTasks<_maxConcurrency && _queue.isNotEmpty){
      // 取出队列第一个task
      final task = _queue.removeFirst();
      _runningTasks++;

      // 真正开始执行这个任务
      task.execute().whenComplete((){
        // 任务跑完（不管成功失败），释放这个"并发名额"
        _runningTasks--;
        // 递归调用自己，看看现在空出来的位置能不能塞进下一个排队任务
        _processQueue();
      });
    }
  }

  // 还在排队、没开始执行的任务数
  int get pendingTasks => _queue.length;

  // 当前正在执行的任务数
  int get runningTasks => _runningTasks;

  // 确认队列是否完全空闲（没有任何任务在跑，也没有任务排队）
  bool get isIdle => _runningTasks==0 && _queue.isEmpty;
}

class _InferenceTask<T>{
  _InferenceTask({
    required this.task,
    required this.completer,
  });
  // Function(): 表示这是一个“函数”，且括号里什么都没有，说明它是一个不需要传入任何参数的函数。
  // 在任务队列中，当你把一个任务加入队列时，你不希望它立刻开始执行，而是希望它“待命”。
  // 所以，你传给队列的不是一个“正在执行的任务”，而是一个“知道如何去执行任务的说明书”（即这个函数）。等到队列轮到它时，队列才会调用 task() 触发真正的执行。
  final Future<T> Function() task;
  // Completer 是 Dart 中用于手动控制 Future 何时完成的控制器。
  // 在 Dart 中，普通的异步函数（比如网络请求）会自动返回一个 Future，你不需要管它什么时候结束。但是，当你需要自己决定什么时候把结果交还给调用者时，就需要用到 Completer。
  // completer.complete(value)：告诉外界“事情办妥了，这是你要的结果”。
  // completer.completeError(error)：告诉外界“事情搞砸了，这是报错信息”。
  final Completer<T> completer;

  Future<void> execute() async{
    try{
      // 1. 真正去执行那个异步任务，并等待它完成
      final result = await task();
      // 2. 如果成功了，把结果交给 completer
      // 此时，外部通过 enqueue 拿到的那个 Future 就会变成完成状态，并拿到 result
      completer.complete(result);
    } catch (e, stackTrace){
      // 3. 如果执行过程中抛出了任何异常，捕获它
      // 把错误和堆栈信息交给 completer
      // 此时，外部拿到的那个 Future 就会变成错误状态
      completer.completeError(e, stackTrace);
    }
  }
}