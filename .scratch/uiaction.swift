import AppKit
import Foundation

//   swift uiaction.swift activate <pid>
//   swift uiaction.swift move <x> <y> [dwellSeconds]
//   swift uiaction.swift click <x> <y>
let args = CommandLine.arguments
guard args.count >= 2 else { exit(1) }

switch args[1] {
case "activate":
    let pid = pid_t(args[2])!
    NSRunningApplication(processIdentifier: pid)?.activate(
        options: [.activateAllWindows]
    )
    Thread.sleep(forTimeInterval: 0.8)
case "move":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    let dwell = args.count > 4 ? Double(args[4])! : 0.2
    Thread.sleep(forTimeInterval: dwell)
case "click":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.1)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.8)
default:
    exit(1)
}
