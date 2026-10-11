-- Model browser requests and placement.
DirectorClient.modules.models = function(ctx)
    local editorState = ctx.state
    ctx.models = {}

    return function()
        ctx.bridge.editorCallback("openModelBrowser", function(_, callback)
            if not editorState.directorOpen or editorState.captureMode then
                callback({ ok = false, message = "Open Director before browsing models." })
                return
            end
            DirectorModelBrowser.open(editorState.camera, ctx.camera.getCameraState())
            ctx.actions.stopAnimationPreview(true)
            if not DirectorModelBrowser.active then
                callback({ ok = false, message = "Browser closed." })
                return
            end
            editorState.previewing = false
            editorState.pressedKeys = {}
            ctx.camera.resetMotion()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("previewModel", function(data, callback)
            local ok, message = DirectorModelBrowser.preview(data.kind, data.model, data.viewport)
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("modelPreviewView", function(data, callback)
            DirectorModelBrowser.view(data.angle, data.zoom, data.elevation, data.viewport)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("clearModelPreview", function(_, callback)
            DirectorModelBrowser.resetPreview()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("closeModelBrowser", function(_, callback)
            DirectorModelBrowser.close()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("placeBrowserModel", function(data, callback)
            if not DirectorModelBrowser.active then
                callback({ ok = false, message = "Open the model browser first." })
                return
            end
            DirectorModelBrowser.close()
            local ok, message = ctx.scene.sceneAdd(data.kind, data.model)
            callback({ ok = ok, message = message })
        end)
    end
end
