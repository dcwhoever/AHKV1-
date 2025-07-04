#NoEnv
SetBatchLines -1
class InputInterceptor {
    static Instances := {}
    static ExitRegistered := false
    static ActiveKeys := {}
    
    __New(ahi, physicalMouseId, physicalKeyboardId := 0) {
        this.ahi := ahi
        this.physicalMouseId := physicalMouseId
        this.physicalKeyboardId := physicalKeyboardId
        this.active := false
        this.configs := Object()
        this.debugMode := false
        this.lastActionTime := A_TickCount
        this.timers := {}            
        DllCall("Winmm.dll\timeBeginPeriod", "uint", 1)
        Random, randNum, 1, 1000000
        this.instanceID := "InputInterceptor_" . A_TickCount . "_" . randNum
        if (!InputInterceptor.ExitRegistered) {
            OnExit("InputInterceptorExitHandler")
            InputInterceptor.ExitRegistered := true
        }
    }
    ConfigureInput(deviceType, physicalButton, config) {
        this.Unsubscribe(deviceType, physicalButton)
        key := deviceType . "_" . physicalButton
        config.physicalButton := physicalButton
        config.deviceType := deviceType
        config.isRapidFiring := false  
        config.rapidFireTimer := "" 
        config.priority := config.HasKey("priority") ? config.priority : 1 
        this.configs[key] := config
        if (deviceType = "mouse") {
            this.ahi.SubscribeMouseButton(this.physicalMouseId, physicalButton, true
                , ObjBindMethod(this, "HandleMouseEvent", physicalButton))
        } 
        else if (deviceType = "keyboard") {
            this.ahi.SubscribeKey(this.physicalKeyboardId, physicalButton, true
                , ObjBindMethod(this, "HandleKeyboardEvent", physicalButton))
        }        
        this.active := true
        InputInterceptor.Instances[this.instanceID] := this
        
        if (this.debugMode)
            this.UpdateDebugInfo("已配置: " . key . " | 类型: " . config.actionType . " | 优先级: " . config.priority)
    }
    HandleMouseEvent(buttonId, state) {
        key := "mouse_" . buttonId
        return this.ProcessEvent(key, state)
    }
    HandleKeyboardEvent(code, state) {
        key := "keyboard_" . code
        return this.ProcessEvent(key, state)
    }
    HasHigherPriorityActive(currentKey) {
        currentConfig := this.configs[currentKey]
        if (!currentConfig)
            return false
            
        currentPriority := currentConfig.priority
        for key, state in InputInterceptor.ActiveKeys {
            if (key != currentKey && state && this.configs.HasKey(key)) {
                otherConfig := this.configs[key]
                if (otherConfig.priority > currentPriority) {
                    return true
                }
            }
        }
        return false
    }
    ForceStopKey(key, config) {
        if (config.actionType = "key") {
            this.TriggerKeyAction(config, "up")
        }
        if (config.isRapidFiring) {
            this.StopRapidFire(key, config, true, false)
        }
    }
    HandleLowerPriorityKeys(currentKey, state) {
        currentConfig := this.configs[currentKey]
        if (!currentConfig)
            return
            
        currentPriority := currentConfig.priority
        if (state == 1) {
            for key, config in this.configs {
                if (key == currentKey || !InputInterceptor.ActiveKeys[key])
                    continue
                if (config.priority < currentPriority) {
                    this.ForceStopKey(key, config)
                    config.suppressedBy := currentKey
                }
            }
        }
        else if (state == 0) {
            for key, config in this.configs {
                if (config.suppressedBy != currentKey)
                    continue
                hasHigherActive := false
                for otherKey, otherState in InputInterceptor.ActiveKeys {
                    if (otherKey != key && otherKey != currentKey && otherState && this.configs.HasKey(otherKey)) {
                        otherConfig := this.configs[otherKey]
                        if (otherConfig.priority > config.priority) {
                            hasHigherActive := true
                            config.suppressedBy := otherKey 
                            break
                        }
                    }
                }
                if (!hasHigherActive && InputInterceptor.ActiveKeys[key]) {
                    config.suppressedBy := ""  
                    if (config.actionType = "key") {
                        this.TriggerKeyAction(config, "down")
                    }
                    if (config.HasKey("rapidFire") && config.rapidFire && config.holdToFire) {
                        this.StartRapidFire(key, config)
                    }
                }
            }
        }
    }
    ProcessEvent(key, state) {
        config := this.configs[key]
        if (!config) {
            return true 
        }
        InputInterceptor.ActiveKeys[key] := state
        if (config.paused) {
            if (config.deviceType = "mouse") {
                this.ahi.SendMouseButtonEvent(this.physicalMouseId, config.physicalButton, state)
            } else {
                this.ahi.SendKeyEvent(this.physicalKeyboardId, config.physicalButton, state)
            }
            if (state == 0) {
                this.StopRapidFire(key, config, false, false) 
                config.suppressedBy := ""
            }            
            return false
        }
        if (this.HasHigherPriorityActive(key)) {
            this.ForceStopKey(key, config)
            if (this.debugMode)
                this.UpdateDebugInfo("按键 " . key . " 被更高优先级阻止")
            return false
        }
        this.HandleLowerPriorityKeys(key, state)
        if (state == 0) {
            this.ForceStopKey(key, config)
            currentPriority := config.priority
            for otherKey, otherState in InputInterceptor.ActiveKeys {
                if (otherKey != key && otherState && this.configs.HasKey(otherKey)) {
                    otherConfig := this.configs[otherKey]
                    if (otherConfig.priority == currentPriority) {
                        if (!otherConfig.suppressedBy) { 
                            if (otherConfig.actionType = "key") {
                                this.TriggerKeyAction(otherConfig, "down")
                            }
                            if (otherConfig.HasKey("rapidFire") && otherConfig.rapidFire && otherConfig.holdToFire && !otherConfig.isRapidFiring) {
                                this.StartRapidFire(otherKey, otherConfig)
                            }
                        }
                    }
                }
            }
            
            return false
        }
        if (state == 1) {
            this.ForceStopKey(key, config)
            if (config.actionType = "function") {
                funcName := config.target
                if (IsFunc(funcName)) {
                    if (config.HasKey("rapidFire") && config.rapidFire) {
                        if (!config.holdToFire) {
                            if (config.isRapidFiring) {
                                this.StopRapidFire(key, config)
                            } else {
                                this.StartRapidFire(key, config)
                            }
                        } 
                        else {
                            this.StartRapidFire(key, config)
                        }
                    } else {
                        if (config.HasKey("params") && IsObject(config.params)) {
                            %funcName%(config.params*)
                        } else {
                            %funcName%()
                        }
                    }
                }
            }
            else if (config.actionType = "key") {
                if (config.HasKey("rapidFire") && config.rapidFire) {
                    if (!config.holdToFire) {
                        if (config.isRapidFiring) {
                            this.StopRapidFire(key, config)
                        } else {
                            this.StartRapidFire(key, config)
                        }
                    } 
                    else {
                        this.StartRapidFire(key, config)
                    }
                } else {
                    this.TriggerKeyAction(config, "down")
                }
            }
            if (config.passOriginal) {
                if (config.deviceType = "mouse") {
                    this.ahi.SendMouseButtonEvent(this.physicalMouseId, config.physicalButton, 1)
                } else {
                    this.ahi.SendKeyEvent(this.physicalKeyboardId, config.physicalButton, 1)
                }
            }
        }
        
        return false
    }
    StartRapidFire(key, config) {
        this.StopRapidFire(key, config, true)
        config.isRapidFiring := true
        this.DoRapidFire(key, config)
        timerFn := ObjBindMethod(this, "DoRapidFire", key, config)
        this.timers[key] := timerFn
        SetTimer, % timerFn, % config.interval
    }
    StopRapidFire(key, config, silent := false, keepState := false) {
        if (this.timers.HasKey(key)) {
            timerFn := this.timers[key]
            SetTimer, % timerFn, Off
            this.timers.Delete(key)
        }
        if (!config.isRapidFiring)
            return
        if (!keepState) {
            config.isRapidFiring := false
        }
        if (!silent && config.actionType = "key") {
            this.TriggerKeyAction(config, "up")
        }
    }
    
    PauseInput(deviceType := "", physicalButton := "") {
        if (deviceType == "" && physicalButton == "") {
            for key, config in this.configs {
                if (config.paused)
                    continue
                config.paused := true
                if (config.isRapidFiring) {
                    this.StopRapidFire(key, config, false, true)
                }
            }
            if (this.debugMode)
                this.UpdateDebugInfo("已暂停所有输入")
            return
        }
        key := deviceType . "_" . physicalButton
        if (this.configs.HasKey(key)) {
            config := this.configs[key]
            if (config.paused)
                return
                
            config.paused := true
            if (config.isRapidFiring) {
                this.StopRapidFire(key, config, false, true)
            }
            
            if (this.debugMode)
                this.UpdateDebugInfo("已暂停: " . key)
        }
    }
    ResumeInput(deviceType := "", physicalButton := "") {
        if (deviceType == "" && physicalButton == "") {
            for key, config in this.configs {
                if (!config.paused)
                    continue
                config.paused := false
                if (config.isRapidFiring) {
                    this.StartRapidFire(key, config)
                }
            }
            if (this.debugMode)
                this.UpdateDebugInfo("已恢复所有输入")
            return
        }
        key := deviceType . "_" . physicalButton
        if (this.configs.HasKey(key)) {
            config := this.configs[key]
            if (!config.paused)
                return
            config.paused := false
            if (config.isRapidFiring) {
                this.StartRapidFire(key, config)
            }
            if (this.debugMode)
                this.UpdateDebugInfo("已恢复: " . key)
        }
    }    
    DoRapidFire(key, config) {
        if (config.paused) {
            return
        }       
        if (!config.isRapidFiring)
            return
        pressDelay := config.delay
        releaseDelay := config.delay
        if (config.HasKey("randomDelay") && config.randomDelay) {
            Random, pressDelay, % config.minDelay, % config.maxDelay
            Random, releaseDelay, % config.minDelay, % config.maxDelay
        }
        if (config.actionType = "key") {
            this.TriggerKeyAction(config, "down")
            Sleep,pressDelay
            this.TriggerKeyAction(config, "up")
            Sleep,releaseDelay
        }
        else if (config.actionType = "function") {
            funcName := config.target
            if (IsFunc(funcName)) {
                if (config.HasKey("params") && IsObject(config.params)) {
                    %funcName%(config.params*)
                } else {
                    %funcName%()
                }
                Sleep,releaseDelay
            }
        }
    }
    TriggerKeyAction(config, action) {
        target := config.target
        if (InStr(target, "mouse") = 1) {
            buttonId := SubStr(target, 6)
            if buttonId is not integer
                buttonId := 0
            
            this.ahi.SendMouseButtonEvent(this.physicalMouseId, buttonId, (action = "down" ? 1 : 0))
        }
        else if target is integer
        {
            this.ahi.SendKeyEvent(this.physicalKeyboardId, target, (action = "down" ? 1 : 0))
        }
    }
    Unsubscribe(deviceType, physicalButton) {
        key := deviceType . "_" . physicalButton
        if (this.configs.HasKey(key)) {
            config := this.configs[key]
            this.StopRapidFire(key, config)            
            if (deviceType = "mouse")
                this.ahi.UnsubscribeMouseButton(this.physicalMouseId, physicalButton)
            else if (deviceType = "keyboard")
                this.ahi.UnsubscribeKey(this.physicalKeyboardId, physicalButton)
            this.configs.Delete(key)
            if (this.timers.HasKey(key)) {
                this.timers.Delete(key)
            }
        }
    }
    DisableAll() {
        if (!this.active)
            return            
        for key, config in this.configs.Clone() {
            this.Unsubscribe(config.deviceType, config.physicalButton)
        }
        
        this.configs := Object()
        this.timers := Object()
        this.active := false
        InputInterceptor.Instances.Delete(this.instanceID)
        
        if (this.debugMode) {
            this.UpdateDebugInfo("已禁用所有拦截")
        }
    }
    ForceReleaseAll() {
        try {
            Loop, 5 {
                this.ahi.SendMouseButtonEvent(this.physicalMouseId, A_Index-1, 0)
            }
            for key, config in this.configs {
                if (config.deviceType = "keyboard") {
                    this.TriggerKeyAction(config, "up")
                }
            }
        }
    }   
    UpdateDebugInfo(text) {
        ToolTip % text, A_CaretX+20, A_CaretY+20
    }
}
InputInterceptorExitHandler(exitReason, exitCode) {
    for instanceID, instance in InputInterceptor.Instances.Clone() {
        instance.DisableAll()
        instance.ForceReleaseAll()
    }
    DllCall("Winmm.dll\timeEndPeriod", "uint", 1)
    ToolTip
    return 0
}  