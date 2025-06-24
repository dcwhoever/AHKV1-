近期老玩各种游戏,,用了不少东西,都感觉不够给力,  于是自己弄了个ahk驱动键鼠, 效果还行,分享一个类,  注意有能力的朋友尽量使用带有cpu事件处理的延迟函数, 将不会有粘黏延迟

--功能基于大佬的ahl的拦截订阅模式,感谢大佬们无私的付出  


初始的一坨,,需提前装好Interception和ahl
#include <AutoHotInterception>
#include <AHI键鼠控制类>
global AHI := new AutoHotInterception()
global physicalMouseId := 0
global physicalKeyboardId := 0  
global interceptor := "" 
AHI.ScanMice()
AHI.ScanKeyboards()
mouseId := AHI.GetMouseId(0x24AE, 0x4110)  ; 使用示例ID，实际使用时需要替换
keyboardId := AHI.GetKeyboardId(0x1A2C, 0x2D43) 
if (mouseId && keyboardId) {
	physicalMouseId := mouseId
	physicalKeyboardId := keyboardId
	interceptor := new InputInterceptor(AHI, physicalMouseId, physicalKeyboardId)
	;~ interceptor.debugMode := true	
    } else {        MsgBox, 设备扫描失败!请确保设备已连接并且驱动正确安装。
} 


具体使用场景参考:

====申明方式1, 具体写
    ;~ config1.actionType := "key"  ;"function"  or "key"
    ;~ config1.target := "mouse1"  ; 鼠标右键映射到自身 
    ;~ config1.rapidFire := true    ; 启用连发模式
    ;~ config1.holdToFire := true   ; 按住连发,  不然是切换连发
    ;~ config1.interval := 6       ; 连发触发间隔(ms)
    ;~ config1.delay := 1          ; 基础按弹间延迟   随机延迟时使用下面的随机值
    ;~ config1.randomDelay := true  ; 启用随机延迟
    ;~ config1.minDelay := 6       ; 最小延迟
    ;~ config1.maxDelay := 16       ; 最大延迟
    ;~ config1.passOriginal := false  ;;  true为同时触发原始输入, 连发建议关闭
    ;~ config1.priority: 2   ;;设置优先级  默认1    同时按下的时候 ,越高的越优先执行 
    ;~ interceptor.ConfigureInput("mouse", 1, config1)

--------也可以简化配置,直接映射订阅
interceptor.ConfigureInput("mouse", 1, {actionType: "key",target: "mouse1",rapidFire: true,holdToFire: true,interval: 6,delay: 1,randomDelay: true,minDelay: 6,maxDelay: 16,passOriginal: true}) 
interceptor.ConfigureInput("mouse", 0, {actionType: "key",target: "mouse0",rapidFire: true,holdToFire: true,interval: 6,delay: 1,randomDelay: true,minDelay: 6,maxDelay: 16,passOriginal: true})     
interceptor.ConfigureInput("keyboard", GetKeySC("a"), {actionType: "key",target: GetKeySC("a"),rapidFire: true,holdToFire: true,interval: 6,delay: 1,randomDelay: true,minDelay: 6,maxDelay: 16,passOriginal: true, priority: 2})     
interceptor.ConfigureInput("keyboard", GetKeySC("q"), {actionType: "key",target: GetKeySC("q"),rapidFire: true,holdToFire: true,interval: 6,delay: 1,randomDelay: true,minDelay: 6,maxDelay: 16,passOriginal: true})   
.....
....
... 
----------


=========-=函数形式, 场景,  比如需要压枪功能,压的时候同时运行其他的某些功能,,
TestFunction3(param1 := "", param2 := "", param3 := "") {
    ToolTip, 自定义函数3被调用!`n参数1: %param1%`n参数2: %param2%`n参数3: %param3%, 200, 200
    ;~ SetTimer, RemoveToolTip, 2000
	 ;~ MouseMove,0,15,0,R 
     AHI.SendMouseMove(14, 0, 15)
     interceptor.sleepex3(1)
 	 AHI.SendMouseButtonEvent(13, 0, 1)
	 ;~ Sleep,6
     interceptor.sleepex3(1)
	 AHI.SendMouseButtonEvent(13, 0, 0)         
    return "函数执行成功"
}
    config4 := Object()
    config4.actionType := "function"
    config4.target := "TestFunction2"
    config4.params := ["参数1", "参数2"]
    config4.passOriginal := true
    ....   也可继续添加其他参数
    ...
    interceptor.ConfigureInput("keyboard", GetKeySC("f"), config4)
--------------------





============实际应用场景案例,  类dota游戏特定窗口, 特定区域触发, 输入框的时候不触发~=====   自行发挥
ahiactive := false  ; 标志位
loop {
    if ( (WinExist("A") = ahwn) and !FindText(X, Y, 426,797, 449,820, 0, 0, Text,,0) ) {            
        if (!ahiactive) {
            interceptor.ResumeInput()      ;;不带参  全部开启
            ahiactive := true
        }  ; ========== 条件控制区（鼠标在道具栏区域自动暂停连发,移动出来以后自动恢复连发）==========        
        MouseGetPos, mx, my
        if (my > 930)
            interceptor.PauseInput("mouse", 1)  
        else
            interceptor.ResumeInput("mouse", 1)
        shape:=GetCursorShape()
        if (shape=2116977283)        
            interceptor.PauseInput("mouse", 0)
        else
            interceptor.ResumeInput("mouse", 0)        
        
        ;==============================
    } else {
        if (ahiactive) {            
            interceptor.PauseInput()       ;;不带参  全部停用
            ahiactive := false
        }
    }
    Sleep, 5
}
=============




  
