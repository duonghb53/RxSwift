//
//  Throttle.swift
//  Rx
//
//  Created by Krunoslav Zaher on 3/22/15.
//  Copyright (c) 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class Throttle_<Element, SchedulerType: Scheduler> : Sink<Element>, ObserverType {
    typealias ParentType = Throttle<Element, SchedulerType>
    typealias ThrottleState = (
        value: Element?,
        cancellable: SerialDisposable,
        id: UInt64
    )
    
    let parent: ParentType
    
    var lock = Lock()
    var throttleState: ThrottleState = (
        value: nil,
        cancellable: SerialDisposable(),
        id: 0
    )
    
    init(parent: ParentType, observer: ObserverOf<Element>, cancel: Disposable) {
        self.parent = parent
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let cancellable = self.throttleState.cancellable
        let subscription = parent.source.subscribe(self)
        
        return CompositeDisposable(subscription, cancellable)
    }

    func on(event: Event<Element>) {
        switch event {
        case .Next:
            break
        case .Error: fallthrough
        case .Completed:
            throttleState.cancellable.dispose()
            break
        }
        
       
        var (latestId: UInt64, observer: ObserverOf<Element>, oldValue: Element?) = self.lock.calculateLocked {
            let observer = self.observer
            
            var oldValue = self.throttleState.value
            
            switch event {
            case .Next(let boxedValue):
                self.throttleState.value = boxedValue.value
            case .Error(let error):
                self.dispose()
                self.throttleState.value = nil
            case .Completed:
                self.dispose()
                self.throttleState.value = nil
            }
            
            self.throttleState.id = self.throttleState.id + 1
            return (self.throttleState.id, observer, oldValue)
        }
        
        
        switch event {
        case .Next(let boxedValue):
            let d = SingleAssignmentDisposable()
            self.throttleState.cancellable.setDisposable(d)
            
            let scheduler = self.parent.scheduler
            let dueTime = self.parent.dueTime
            
            let _  = scheduler.scheduleRelative(latestId, dueTime: dueTime) { (id) in
                return success(self.propagate())
            } >== { disposeTimer -> Result<Void> in
                d.setDisposable(disposeTimer)
                return SuccessResult
            } >>! { e -> Result<Void> in
                self.observer.on(.Error(e))
                self.dispose()
                return SuccessResult
            }
        case .Error(let error):
            return observer.on(.Error(error))
        case .Completed:
            if let oldValue = oldValue {
                observer.on(.Next(Box(oldValue)))
            }
            
            observer.on(.Completed)
        }
    }
    
    func propagate() {
        var originalValue: Element? = self.lock.calculateLocked {
            var originalValue = self.throttleState.value
            self.throttleState.value = nil
            return originalValue
        }
        
        if let value = originalValue {
            self.observer.on(.Next(Box(value)))
        }
    }
}

class Throttle<Element, SchedulerType: Scheduler> : Producer<Element> {
    
    let source: Observable<Element>
    let dueTime: SchedulerType.TimeInterval
    let scheduler: SchedulerType
    
    init(source: Observable<Element>, dueTime: SchedulerType.TimeInterval, scheduler: SchedulerType) {
        self.source = source
        self.dueTime = dueTime
        self.scheduler = scheduler
    }
    
    override func run(observer: ObserverOf<Element>, cancel: Disposable, setSink: (Disposable) -> Void) -> Disposable {
        let sink = Throttle_(parent: self, observer: observer, cancel: cancel)
        setSink(sink)
        return sink.run()
    }
    
}