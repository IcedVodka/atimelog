## 现状
Phase 2 (Refinement & UI) 需求开发文档.md的需求目前的代码已基本实现，有些bug和功能不符预期。


## 修正目标

### 活动页面
分类网格太大了，分类网格小一点，每行可供选择活动多一些。
手动补录的时候，选择不同的活动，记录内容不会同步改变，这是个bug，要修改。

### 分类管理界面
重构目前的组逻辑，每个分类只有一个叫名称的名字，没有组名字，组逻辑是暗含在名称格式里面的。
除了午睡外，目前的活动保持名字，上网探究，刷视频，通勤等等。午睡重命名为睡眠.午睡，睡眠.午睡在存储上是一个和上网探究和睡眠同等地位的活动，只是在统计页面展示时，如果勾选了合并组，合并到睡眠去展示，希望这个例子能让你知道我所构想的组逻辑。

分类管理界面一行放一个中间空太多太单调不美观，改为一行放两个。

颜色和图标还是不够多，想想有什么办法能显著增加可选择颜色和图标。

### 统计页面

如果查询到json数据里面有活动的名称没有定义，展示的时候以其他.名称展示，就是归类到「其他」这个隐含的组。

#### 时间线

时间线展示每个活动的时候，加黑加粗显示活动标题，活动标题就是分类名称注意不是记录内容。
活动列表展示的东西总计时间，单列时长，起止时间，记录内容字太少了，而且一行一列右半边全是空的，可以琢磨琢磨怎么样展示更加美观。

有一个bug需要修复，如果一个活动是跨天的，因为存储问题，活动会被分成到两天里，但是记录内容的修改并不会同步修改，这个bug要修复。

#### 饼图
时间范围的底下分列的活动数据字体大一些，太小了。

时间范围和底下分列的活动数据中间那个灰色的框删掉，不需要。

底下分列的活动数据一排过去，有些丑，想办法怎么美化一下。

## 运行记录（可能包含报错信息）

gml-cwl@gmlrobot:~/code2/atimelog_demo$ flutter run -d linux 
Launching lib/main.dart on Linux in debug mode...
Building Linux application...                                           
✓ Built build/linux/x64/debug/bundle/atimelog_demo
Syncing files to device Linux...                                    40ms

Flutter run key commands.
r Hot reload. 🔥🔥🔥
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application running).
c Clear the screen
q Quit (terminate the application on the device).

A Dart VM Service on Linux is available at: http://127.0.0.1:38267/R7OMlBfH6-E=/
The Flutter DevTools debugger and profiler on Linux is available at:
http://127.0.0.1:38267/R7OMlBfH6-E=/devtools/?uri=ws://127.0.0.1:38267/R7OMlBfH6
-E=/ws

══╡ EXCEPTION CAUGHT BY ANIMATION LIBRARY
╞═════════════════════════════════════════════════════════
The following assertion was thrown while notifying status listeners for
AnimationController:
The provided ScrollController is attached to more than one ScrollPosition.
The Scrollbar requires a single ScrollPosition in order to be painted.
When the scrollbar is interactive, the associated ScrollController must only
have one ScrollPosition
attached.
The provided ScrollController cannot be shared by multiple ScrollView widgets.

When the exception was thrown, this was the stack:
#0      RawScrollbarState._debugCheckHasValidScrollPosition.<anonymous closure>
(package:flutter/src/widgets/scrollbar.dart:1532:9)
#1      RawScrollbarState._debugCheckHasValidScrollPosition
(package:flutter/src/widgets/scrollbar.dart:1560:6)
#2      RawScrollbarState._validateInteractions
(package:flutter/src/widgets/scrollbar.dart:1467:14)
#3      AnimationLocalStatusListenersMixin.notifyStatusListeners
(package:flutter/src/animation/listener_helpers.dart:242:19)
#4      AnimationController._checkStatusChanged
(package:flutter/src/animation/animation_controller.dart:941:7)
#5      AnimationController._startSimulation
(package:flutter/src/animation/animation_controller.dart:874:5)
#6      AnimationController._animateToInternal
(package:flutter/src/animation/animation_controller.dart:687:12)
#7      AnimationController.reverse
(package:flutter/src/animation/animation_controller.dart:521:12)
#8      RawScrollbarState._maybeStartFadeoutTimer.<anonymous closure>
(package:flutter/src/widgets/scrollbar.dart:1613:37)
#12     _RawReceivePort._handleMessage
(dart:isolate-patch/isolate_patch.dart:193:12)
(elided 3 frames from class _Timer and dart:async-patch)

The AnimationController notifying status listeners was:
  AnimationController#e3da8(◀ 1.000)
════════════════════════════════════════════════════════════════════════════════
════════════════════
