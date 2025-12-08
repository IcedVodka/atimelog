# AtimeLog Clone - Phase 2 (Refinement) 需求开发文档

版本: 2.0 (Draft)

依赖基础: Phase 1 (Foundation - 数据读写层完成)

核心目标: 完成核心 UI 交互，实现“看起来像有暂停功能，实际上是归档逻辑”的无缝体验，并完善统计与配置功能。

---

## 1. 页面一：活动主页 (Home / Activity)

此页面是应用的核心，对应 Screenshot 1 (活动列表) & Screenshot 4 (活动进行中)。

### 1.1 界面布局 (UI Layout)

页面垂直分为两个区域：

1. **顶部：活动看板 (The Dashboard)**
    
    - **正在进行 (Active):** 显示当前计时任务（如有）。显示项：图标、名称、**动态跳动的计时**。
        
        - _操作按钮:_ [暂停 (蓝)]、[停止 (红)]。
            
    - **最近活动 (Recent Contexts):** 显示在 `current_session.json` -> `recentContexts` 中的任务（即截图中的“暂停状态”任务）。
        
        - _显示项:_ 图标、名称、已记录时长（静态）。
            
        - _操作按钮:_ [继续 (绿)]、[移除 (红)]。
            
2. **底部：分类网格 (Category Grid)**
    
    - 对应 Screenshot 2 (类别)。
        
    - 显示所有可用分类的图标和名称。
        

### 1.2 交互逻辑 (Interaction Logic)

**关键点：** UI 上呈现的“暂停”状态，在底层逻辑中对应“**已归档但保留在 Recent 列表**”。

#### A. 操作：正在进行 (Active)

- **点击 [暂停 (蓝)]**:
    
    1. 执行 **Stop** 逻辑（结算当前时长，写入 `YYYY-MM-DD.json`）。
        
    2. 将该任务推入 `recentContexts` 列表顶端（UI 上变为“暂停”状态）。
        
    3. 清空 `current`。
        
- **点击 [停止 (红)]**:
    
    1. 执行 **Stop** 逻辑（结算并归档）。
        
    2. **不**推入 `recentContexts`（或者从 Recent 中移除）。
        
    3. _效果:_ 任务彻底结束，从顶部看板消失。
        
- **点击 [修改 (Edit)]**:
    
    1. 允许修正当前正在进行的 `startTime`。
        

#### B. 操作：最近活动/暂停项 (Recent)

- **点击 [继续 (绿)]**:
    
    1. 读取该项的 `groupId`。
        
    2. 执行 **Switch** 逻辑（如果当前有任务，先停止当前）。
        
    3. 执行 **Resume** 逻辑（复用 `groupId`，写入 `current`，开始新计时）。
        
    4. _效果:_ 该条目变回“正在进行”。
        
- **点击 [停止/移除 (红)]**:
    
    1. 仅操作 `current_session.json`。
        
    2. 从 `recentContexts` 列表中移除该项。
        
    3. _注意:_ **不删除**历史数据，仅从快捷看板中移除。
        

#### C. 操作：分类网格 (Category Grid)

- **点击任意分类图标**:
    
    1. 执行 **Switch** 逻辑（停止当前，若有）。
        
    2. 生成**新** `groupId`，开始全新任务。
        
- **长按分类图标**:
    
    1. 弹出“手动添加记录”对话框（补录忘记记的时间）。
        

---

## 2. 页面二：统计与图表 (Statistics)

对应 Screenshot 3 (菜单) & Screenshot 3 (饼图)。

### 2.1 导航结构

通过顶部 Tab 或 侧边栏/下拉菜单 切换以下子视图：

1. **活动历史清单 (Timeline List)**
    
    - **数据源:** `data/YYYYMM/YYYY-MM-DD.json`。
        
    - **聚合显示:**
        
        - 同一天内，相同 `groupId` 的碎片记录需在视觉上合并（显示总起止时间，或显示“总时长 + 碎片详情”）。
            
    - **编辑功能:** 点击记录可修改 `startTime`, `endTime`, `note`，或删除记录。
        
2. **饼图界面 (Pie Chart)**
    
    - **维度:** 按 `categoryId` 汇总时长。
        
    - **交互:** 点击扇区显示具体时长和百分比。
        
    - **范围:** 默认“今日”，可切换“本周/本月”。
        
3. **高级统计 (Advanced) - (可选/P3)**
    
    - 柱状图（每日时长趋势）。
        

---

## 3. 页面三：分类管理 (Categories)

管理 `config/categories.json` 文件。

### 3.1 功能需求

1. **列表展示:** 显示所有分类，支持拖拽排序 (`order` 字段)。
    
2. **新建/编辑:**
    
    - 输入名称 (Name)。
        
    - 选择图标 (Icon Picker)。
        
    - 选择颜色 (Color Picker)。
        
    - 归属父组 (Group) - _用于截图中的“分组”概念_。
        
3. **删除:** 软删除或标记为停用（避免历史数据关联失效）。
    

---

## 4. 页面四：更多与设置 (Settings)

对应 Screenshot 1 (更多菜单)。

### 4.1 核心设置

1. **备份与恢复:** 导出/导入 `/atimelog_data` 文件夹的压缩包。
    
2. **主题:** 亮色/暗色模式切换。
    
3. **关于:** 版本号显示。
    

---

## 5. 后端逻辑补充 (Technical Refinement for P2)

为了支持上述 UI，Phase 2 必须在底层实现以下关键逻辑：

### 5.1 午夜切断 (Midnight Split) - **P2 重点**

- **场景:** 用户开启“睡眠”并在第二天早上醒来停止。
    
- **逻辑:**
    
    - App 必须有一个 Timer 或在 `onResume` 时检查：`Current.startTime` 是否属于“昨天”。
        
    - 如果是，自动执行“切断”：
        
        1. 结束当前任务于 23:59:59 (归档至昨日)。
            
        2. 新建任务于 00:00:00 (归档至今日，`groupId` 不变)。
            
        3. 更新 `current_session` 的 `startTime` 为 00:00:00。
            

### 5.2 数据修正 (Data Correction)

- 提供 API：`updateRecord(date, recordId, newStart, newEnd)`。
    
- **难点:** 修改时间可能导致时间重叠 (Overlaps)。
    
- **P2 策略:** 允许重叠，但在 UI 上给予警告，或简单的自动截断重叠部分。
    

---

## 6. 开发优先级 (Priority Checklist)

1. [ ] **UI骨架搭建:** 实现底部导航或顶部菜单结构。
    
2. [ ] **Home - 交互核心:** 完成 开始/停止/暂停/继续 的逻辑闭环（打通 `current_session.json`）。
    
3. [ ] **Home - 分类网格:** 实现从 `categories.json` 读取并渲染。
    
4. [ ] **Stats - 历史列表:** 实现 JSON 数据的按日读取与列表渲染。
    
5. [ ] **Stats - 饼图:** 引入图表库 (如 `fl_chart`) 展示数据。
    
6. [ ] **Logic - 午夜跨天:** 处理跨天计时 bug。
    
