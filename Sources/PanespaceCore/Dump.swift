import CoreGraphics

/// JSON-ready snapshots for `panespace msg -t get_tree` / `get_workspaces`.
extension Model {
    public func workspacesJSON() -> [[String: Any]] {
        sortedWorkspaces.map { ws in
            [
                "name": ws.name,
                "num": ws.number ?? -1,
                "output": monitor(ws.monitorID)?.name ?? "",
                "visible": isVisible(ws),
                "focused": ws === focusedWorkspace,
                "windows": ws.allWindows.count,
            ]
        }
    }

    public func treeJSON() -> [String: Any] {
        func rect(_ r: CGRect) -> [String: Int] {
            ["x": Int(r.minX), "y": Int(r.minY), "width": Int(r.width), "height": Int(r.height)]
        }
        func window(_ w: WindowNode, _ ws: Workspace?) -> [String: Any] {
            var d: [String: Any] = [
                "type": "window", "id": Int(w.id), "app": w.info.app, "bundle_id": w.info.bundleID,
                "title": w.info.title, "floating": w.isFloating, "weight": Double(w.weight),
                "focused": w === focusedWindow, "fullscreen": ws?.fullscreen === w,
            ]
            if let f = w.isFloating ? w.floatingFrame : w.rect { d["rect"] = rect(f) }
            return d
        }
        func node(_ n: Node, _ ws: Workspace) -> [String: Any] {
            if let w = n as? WindowNode { return window(w, ws) }
            let c = n as! Container
            return [
                "type": "con", "layout": c.layout.rawValue, "weight": Double(c.weight), "rect": rect(c.rect),
                "focused": c === ws.selected, "nodes": c.children.map { node($0, ws) },
            ]
        }
        return [
            "mode": mode,
            "outputs": monitors.map { m in
                [
                    "name": m.name, "id": Int(m.id), "primary": m.isMain, "rect": rect(m.frame),
                    "current_workspace": visible[m.id]?.name ?? "",
                    "workspaces": sortedWorkspaces.filter { $0.monitorID == m.id }.map { ws in
                        [
                            "name": ws.name, "visible": isVisible(ws), "focused": ws === focusedWorkspace,
                            "layout": ws.root.layout.rawValue, "nodes": ws.root.children.map { node($0, ws) },
                            "floating_nodes": ws.floating.map { window($0, ws) },
                        ] as [String: Any]
                    },
                ] as [String: Any]
            },
            "scratchpad": scratchpad.map { window($0, nil) },
        ]
    }
}
