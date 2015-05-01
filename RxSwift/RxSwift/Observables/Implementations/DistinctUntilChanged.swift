//
//  DistinctUntilChanged.swift
//  Rx
//
//  Created by Krunoslav Zaher on 3/15/15.
//  Copyright (c) 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class DistinctUntilChanged_<ElementType, Key>: Sink<ElementType>, ObserverType {
    typealias Element = ElementType
    
    let parent: DistinctUntilChanged<ElementType, Key>
    var currentKey: Key? = nil
    
    init(parent: DistinctUntilChanged<ElementType, Key>, observer: ObserverOf<ElementType>, cancel: Disposable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(event: Event<Element>) {
        let observer = super.state.observer
        
        switch event {
        case .Next(let value):
            let keyResult = self.parent.selector(value.value)
                
            let areEqualResult = keyResult >== { key -> Result<Bool> in
                if let currentKey = self.currentKey {
                    return self.parent.comparer(currentKey, key)
                }
                else {
                    return success(false)
                }
            } >== { areEqual in
                if areEqual {
                    return SuccessResult
                }
                
                self.currentKey = *keyResult
                
                observer.on(event)
                return SuccessResult
            } >>! { error -> Result<Void> in
                observer.on(.Error(error))
                self.dispose()
                return SuccessResult
            }
        case .Error: fallthrough
        case .Completed:
            observer.on(event)
            self.dispose()
        }
    }
}

class DistinctUntilChanged<Element, Key>: Producer<Element> {
    typealias KeySelector = (Element) -> Result<Key>
    typealias EqualityComparer = (Key, Key) -> Result<Bool>
    
    let source: Observable<Element>
    let selector: KeySelector
    let comparer: EqualityComparer
    
    init(source: Observable<Element>, selector: KeySelector, comparer: EqualityComparer) {
        self.source = source
        self.selector = selector
        self.comparer = comparer
    }
    
    override func run(observer: ObserverOf<Element>, cancel: Disposable, setSink: (Disposable) -> Void) -> Disposable {
        let sink = DistinctUntilChanged_(parent: self, observer: observer, cancel: cancel)
        setSink(sink)
        return source.subscribe(sink)
    }
}