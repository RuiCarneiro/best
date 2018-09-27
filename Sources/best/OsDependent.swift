//  Copyright © 2018 Rui Carneiro. All rights reserved.

import Foundation

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Darwin
#elseif os(Linux) || os(FreeBSD) || os(PS4) || os(Android)
import Glibc
#endif

class OSDependent {
    static func exit(code: Int32) {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        Darwin.exit(code)
        #elseif os(Linux) || os(FreeBSD) || os(PS4) || os(Android)
        Glibc.exit(code)
        #endif
    }

    static var invalidArgumentErrorCode: Int32 {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        return Darwin.EINVAL
        #elseif os(Linux) || os(FreeBSD) || os(PS4) || os(Android)
        return Glibc.EINVAL
        #endif
    }
}
