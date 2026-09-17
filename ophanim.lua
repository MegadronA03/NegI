--TODOs:
-- 1. Host representation. Lua have quite messy syntax and context, we need to nicely wrap this up inside some Manifest or Frame.
-- 2. Just finish manifests (Especially Error, to check if we getting stuck in halt)
-- 3. Tokens should keep track of current evaluated data by having access to the Host device (like Artifacts do), but here in PoC we just refere to it directly through FISH due to "it's convinient" and "that stuff is depandant on host"

return (function ()
    --Frontend: NegI - Negotiation Interface/Negate Identity (the interface, what is developed, that's the front name)
    --Backend: OPHANIM - Ontological Polymorphic Host for Authority and Negotiation Interface Management (the substrate, NegI implementation)
    local pprint = require("pprint") -- remove after fixing problems
    --local ldbg = require("lua_utils/debugger")
    -- This works more or less as ship of thesus, OPHANIM provides common interfaces for other manifests to communicate with each other in platform agnostic way
    local newstate = function () -- something similar to lua_newstate but for OPHANIM
        local table_invert = function (t)
            local s={}
            for k,v in pairs(t) do s[v]=k end
            return s end
        local bimap_write = function(bimap, view_key, index, value)
            -- Input validation
            local reverse_key = (view_key):reverse() -- it's fine because code follows this convention
            if type(bimap) ~= "table" or not view_key or not reverse_key then error("Invalid bimap or keys provided", 2) end

            local fwd_view = bimap[view_key]
            local rev_view = bimap[reverse_key]

            if not fwd_view or not rev_view then error("Invalid view keys provided", 2) end
       
            -- DELETION PATH (value is nil)
            if value == nil then
                if index == nil then error("expected index, got nil", 2) end

                local old_value = fwd_view[index]
                if old_value ~= nil then
                    fwd_view[index] = nil
                    rev_view[old_value] = nil
                end
                return end
       
            -- INSERTION / UPDATE PATH
            -- 1. Clean up any existing mapping for this index
            local old_value = fwd_view[index]
            if old_value ~= nil then rev_view[old_value] = nil end
       
            -- 2. Clean up any existing mapping for this value (enforce 1-to-1)
            local old_index = rev_view[value]
            if old_index ~= nil then fwd_view[old_index] = nil end
       
            -- 3. Write the new mapping
            fwd_view[index] = value
            rev_view[value] = index
        end
        local manifest_reaper = {}
        local FLESH -- forward declaration
        FLESH = { -- stands for "Fixed Local Environment Shared Handles"
            FISH = { -- "Fixed Internal State Holder" - used by particular manifests to pass around some data. Could be avoided via KES, but those values are quite commonly used, so it will influence performance.
                -- probably reserved for parser tokens, but I might leave that up to Tokens themselves
            },
            KES = { -- "Knowledge Environment State" (considered finished, until bugs will be found)
                layers = {{d = 1,h = {r={},i={}},s = {{a={},e={},r={}}},c = {ob={},bo={}},o = {h={},r={},l={}}}}, -- stack of references, string names ready for free (initial layer is preloaded)
                handles = { -- instead of giving out raw layer depths and introducing use after free bugs, we introduce "addresses" to relevant layers
                    lh = {},
                    hl = {}},
                relevance = { -- tracks what currently available in active context
                    dl = {[1]=1}, -- Array<depth: Integer, layer_id: Integer>
                    ld = {[1]=1}}, -- Map<layer_id: Integer, depth: Integer> stores which layers are relevent to current context, mostly used as Set<layer_id: Integer>
                isolations = { -- tracks to which layer unquotation should latch. basically ordered Set<depth: Integer>
                    ["od"] = {}, -- Array<order: Integer, depth: Integer> - we use this to iterate through them
                    ["do"] = {}}, -- Map<depth: Integer, order: Integer> - that the depths of those, also "do" key is the reason I hate keywords
                -- we changed assumptions, now labels will store both numeric and string labels, while bindings won't be acessible directly for the user
                labels = { -- tracks public(String)/anonymic(Number) binding names. BiMap<label: String|Number, bind: Number> holds labeled refences, bimap/not in bindings - because it's an extension that exist only for the user
                    bl = {}, -- Array<bind : Integer, label: String|Integer>
                    lb = {}}, -- Map<label: String|Integer, bind : Integer>
                bindings = {}, -- Array<bind: Integer, {records: Map<layer_id: Integer, entry: Manifest>, order: BiMap<layer_id: Integer, order: Integer>}> holds references to data
                --bindings = ltr.trace.table({},nil,--function (c,t,k) print(string.format("READ AT: %s on %s, key %s:%s", c.name or "<ANON>", c.currentline, tostring(k), tostring(type(k)))) end,
                --    function (c,t,k,v)
                --        print(string.format("WRITE AT: %s on %s, key %s:%s, val %s:%s", c.name or "<ANON>", c.currentline, tostring(k), tostring(type(k)), tostring(v), tostring(type(v))))
                --    end
                --),
               
                resolve = function (self, ref, framed) -- note that strings are names for indicies, "framed" is used by Frame to get data from current Frame
                    if (type(ref) ~= "string" and type(ref) ~= "number") then
                        error("OPHANIM: FLESH.KES:resolve - invalid argument, expected number or string", 2)
                    end
                    local rt
                    if type(ref) == "number" then -- anonymic bindings are always local
                        framed = true
                        rt = self.bindings[self.layers[#self.layers].c.ob[ref]]
                    else
                        rt = self.bindings[self.labels.lb[ref]]
                    end
                    if (rt == nil) then return end -- the environment don't know about this binding so we exit early, this line is optional
                    local m, fh -- data, from_here
                    if (#rt.order.ol > #self.relevance.dl) or framed then -- NOTE: records store changes per each layer, so this checks if it's effective to do vertical or horizontal search traversal
                        for d = #self.relevance.dl, framed and #self.relevance.dl or 1, -1 do -- inverse order, because we pick fresh ones, in order to hit early
                            local l = self.relevance.dl[d]
                            if rt.order.lo[l] then
                                m = rt.records[l] -- we do not use rt.records[e], because it may contain nil, due to "namespace" reservation
                                fh = (#self.layers == l)
                            break end
                        end
                    else
                        for o = #rt.order.ol, 1, -1 do -- inverse order, because we pick fresh ones, in order to hit early
                            local l = rt.order.ol[o]
                            if self.relevance.ld[l] then
                                m = rt.records[l]
                                fh = (#self.layers == l)
                            break end
                        end
                    end
                    return m, fh -- Manifest(lua table, that represnts it) and if this info from current layer
                end,
                push_layer = function (self, parent_depth, isolated) -- adds new layer
                    -- we make an exception for root layer, because there's nothing to isolate against
                    -- initial layer is preloaded, but I still add it if user decide to pop the root layer and there will be those who would like to do that for the fun of it (hi tsoding)
                    local not_root = (#self.relevance.dl > 0)
                    --local parent = self.relevance.dl[parent_depth]
                    if (not_root) then
                        if (type(parent_depth) ~= "number") then error("OPHANIM: FLESH.KES:push_layer - parent_depth<number> expected, got "..type(parent), 2) end -- I also think that root layers should be definable if no parent specified
                        if (parent_depth > self.layers[#self.layers].d or parent_depth < 1) then error("invalid parent depth", 2) end
                        --if (not parent) then error("can't find parent", 2) end
                    end
                    local l = { -- new layer data
                        d = (not_root) and (parent_depth + 1) or 1, -- new layer depth
                        h = {r={},i={}}, -- those are hidden layers (r - relevance, i - isolation)
                        s = {{a={},e={},r={}}}, -- staged entries data: aliases(aka refs), entries and reserved aliases
                        c = {ob={},bo={}}, -- `c` is BiMap<order: Integer, bind: Integer> references relvant to this context layer
                        o = {h={},r={},l={}}} -- ownership data: s - share handles to parent (removed in favour of `stage_stash`), h - Array<handle>, r - WeakMap<handle,reaper>

                    --if (#self.relevance.dl > l.d) then
                        for d = #self.relevance.dl, l.d, -1 do -- exclude all layers between parent and new layer depths via depth
                            l.h.r[#l.h.r+1] = self.relevance.dl[d] -- hide layers (we can ask depth from them directly)
                            bimap_write(self.relevance, "dl", d, nil) -- removing irrelevant layers
                            if self.isolations["do"][d] then -- check if there is isolation
                                l.h.i[#l.h.i+1] = d -- hide isolations (we can ask depth form them directly)
                                bimap_write(self.isolations, "do", d, nil) end end-- end -- removing irrelevant isolations
                    self.layers[#self.layers+1] = l
                    bimap_write(self.relevance, "ld", #self.layers, l.d)
                    if isolated then bimap_write(self.isolations, "od", #self.isolations.od+1, l.d) end -- isolated (external binding resolving, causes it to use resolving oblivious to effects from here)
                    return #self.layers -- used if Sequence will define another Sequence
                end,
                pop_layer = function (self, creturn) -- P.S. while push and pop suggest stack structure, this isn't purely just that due to parent detours
                    if (#self.layers <= 0) then error("FLESH.KES:pop_layer - no layers to pop", 2) end
                    local l = self.layers[#self.layers]--; print("layer: "..tostring(#self.layers))
                    local db = self.bindings

                    if creturn then -- skip lifting, if we don't have anything to lift
                        self:lift_resource(creturn)
                        local res = creturn.protocol and creturn.protocol.res
                        if res then FLESH:do_action(res, creturn, FLESH.NegI.Assets.Lift) end end -- then we lookup for `r`s dependencies, just to move them together
                    for h,r in pairs(l.o.r) do r.state.artifact(h) end

                    for _,b in ipairs(l.c.ob) do -- removing references from bindings
                        local rt = db[b]
                        rt.records[#self.layers] = nil
                        if (#self.layers == rt.order.ol[#rt.order.ol]) then
                            bimap_write(rt.order, "lo", #self.layers, nil)
                        else error("KES:pop_layer - invalid layer in unload transaction query. [Z_Z] Currently I'm thinking to keep it as user error or make code for handling this.", 2) end
                        if #rt.order.ol <= 0 then db[b] = nil; bimap_write(self.labels, "bl", b, nil) end end
                    if self.isolations["do"][l.d] then bimap_write(self.isolations, "do", l.d, nil) end -- lift isolation sandbox (if there is any)
                    bimap_write(self.relevance, "ld", #self.layers, nil) -- removed layer is irrelevant, removing it
                    local hidden_layers = l.h -- there is always hidden entries
                    for _,e in ipairs(hidden_layers.r) do -- restoring hidden context relevance
                        bimap_write(self.relevance, "ld", e, self.layers[e].d) end
                    for i = #hidden_layers.i, 1, -1 do -- restoring hidden context isolations
                        bimap_write(self.isolations, "od", #self.isolations.od + 1, hidden_layers.i[i]) end

                    self.layers[#self.layers] = nil -- removing layer

                    for i,e in pairs(l.o.l) do FLESH:do_action(e.l, e.m) end
                    return creturn
                end,
                unquote_parent = function (self, parent_depth) -- get parent of unquotation
                    local not_root = (#self.relevance.dl > 0)
                    --local parent = self.relevance.dl[parent_depth]
                    if (not_root) then
                        if (type(parent_depth) ~= "number") then error("OPHANIM: FLESH.KES:push_layer - parent_depth<number> expected, got "..type(parent), 2) end -- I also think that root layers should be definable if no parent specified
                        if (parent_depth > self.layers[#self.layers].d or parent_depth < 1) then error("invalid parent depth", 2) end
                    end
                    parent_depth = parent_depth or 0 -- parent depth
                    local iso_depth_i, iso_depth = #self.isolations.od, nil
                    while ((self.isolations.od[iso_depth_i] or 0) > parent_depth) do -- we check if layer definition was outside of isolation. also binary search could be applied here
                        iso_depth = self.isolations.od[iso_depth_i]
                        iso_depth_i = iso_depth_i - 1 end
                    if (iso_depth) then -- if dynamic defined outside isolation, then it shouldn't consider effect of isolation
                        return iso_depth - 1 -- find parent of layer outside of isolation
                    else
                        return self.layers[#self.layers].d
                    end
                end,
                has_resource = function (self, handle) return self.layers[#self.layers].o.r[handle] ~= nil end,
                own_resource = function (self, handle, reaper)
                    local lo = self.layers[#self.layers].o
                    lo.r[handle] = reaper -- not sure about it being `nil`
                    lo.h[#lo.h+1] = handle end,
                lift_resource = function (self, handle) -- may be issues with `.h`
                    local lo = self.layers[#self.layers].o
                    local reaper = lo.r[handle]
                    if not reaper then return end
                    self.layers[#self.layers-1].o.r[handle] = reaper
                    lo.r[handle] = nil
                    if reaper == manifest_reaper then 
                        local lift = handle.protocol and handle.protocol.lift
                        lo.l[#lo.l+1] = {l = lift, m = handle} end
                end,
                get_owner_handle = function (self) end,
                get_context = function (self) return #self.layers end, -- will be probably be deprecated
                get_depth = function (self) return self.layers[#self.layers].d end, -- used by Membranes to memorize context for later use
                write_entry = function (self, ref, m) -- reference : Number|String, [manifest: Any|Nil]
                    local db = self.bindings
                    local c = self.layers[#self.layers].c
                    local b = (#db + 1)
                    local order = (#c.ob + 1)
                    if ref then
                        if (type(ref) ~= "string") then error("on ref expected string or nil, got "..type(ref), 2) end
                        b = self.labels.lb[ref] or b
                        bimap_write(self.labels, "lb", ref, b)
                    else ref = order end
                    db[b] = db[b] or { records = {}, order = {ol = {}, lo = {}} }
                    db[b].records[#self.layers] = m -- note that nil will reserve the place on layer
                    --TODO: unite the check
                    if not db[b].order.lo[#self.layers] then -- do we need to add new or just update the binding
                        bimap_write(db[b].order, "ol", #(db[b].order.ol) + 1, #self.layers)
                    end
                    if not c.bo[b] then -- if it's new binding for this context
                        bimap_write(c, "bo", b, order)
                    end
                    return ref
                end, -- entry writes could only happen in current context
                stage_push = function (self)
                    local ls = self.layers[#self.layers].s
                    ls[#ls + 1] = {a={},e={},r={}}
                end, -- maybe commit will remove this "layer" ?
                stage_pop = function (self)
                    local ls = self.layers[#self.layers].s
                    ls[#ls] = nil
                end,
                stage_resolve_id = function (self, ref) return self.layers[#self.layers].s.a[ref] end,
                stage_entry = function (self, data, stage_id) -- when `ref` is present, it updates info that references existing entry
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    if stage_id and stage_id > #stage.e then error("FLESH.KES:stage_entry - stage_id points to undefined entry.", 2) end
                    if stage_id then -- explicit abscense of stage_id, will make a new entry
                        stage.e[stage_id].d = data
                        if stage.e[stage_id].r then
                            stage.r[stage.e[stage_id].r] = nil
                            stage.e[stage_id].r = nil end
                    else
                        stage_id = #stage.e+1
                        stage.e[stage_id] = {a={},r=nil,d=data} end -- a - aliases (holds both anonym bindings and label names), r - reserved (even nil might be the data, so we need to track this separately), d - data
                    return stage_id
                end,
                stage_alias = function (self, ref, stage_id)  -- when `ref` is present, it updates info that references existing entry
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    if not stage then 
                        pprint(self.layers[#self.layers].s)
                    end
                    if stage_id and stage_id > #stage.e then error("FLESH.KES:stage_alias - stage_id points to undefined entry.", 2) end
                    if stage_id then -- explicit abscense of stage_id, will make a new entry
                        stage.e[stage_id].a[#stage.e[stage_id].a +1] = ref
                    else
                        stage_id = #stage.e+1
                        stage.r[#stage.r +1] = stage_id
                        stage.e[stage_id] = {a={ref},r=#stage.r,d=nil} end -- a - aliases (holds both anonym bindings and label names), r - reserved (even nil might be the data, so we need to track this separately), d - data
                    stage.a[ref] = stage_id -- label can point only to one place, we don't discourage user from that
                    return stage_id
                end,
                stage_staged = function (self)
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    return #stage.e
                end,
                stage_reserved = function (self)
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    return #stage.r > 0
                end,
                stage_fill_reserve = function (self, data)
                    if (data == FLESH.NegI.RootContext.gap) then data = nil end -- somewhat hacky, but good enough for a `gap` check. Resource might not like this
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    for _,i in ipairs(stage.r) do self:stage_entry(data, i) end
                    stage.r = {}
                end,
                stage_commit = function (self, write) -- apply staged changes
                    --print("==== commit ====")
                    --print("\tlayer:"..tostring(#self.layers))
                    --print("\tdepth:"..tostring(self.layers[#self.layers].d))
                    --print("\tisolated:"..tostring(self.isolations["do"][self.layers[#self.layers].d] ~= nil))
                    --print("\tcontent:")
                    --pprint(self.layers[#self.layers].s.a)
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    write = write or function () end
                    for _, e in ipairs(stage.e) do
                        if (#e.a > 0) then for _, name in ipairs(e.a) do
                            --print("\t+ "..name)
                            write(name, e.d) end
                        else write(nil, e.d) end end
                    ls[#ls] = {a={},e={},r={}} -- a - aliases, e - entries, r - reserve
                end,
                stage_snapshot = function (self, frame_state) -- alternate for inner_snapshot, just for the Frames
                    frame_state = frame_state or {labels = {lb={},bl={}}, bindings = {}}
                    local ls = self.layers[#self.layers].s
                    local stage = ls[#ls]
                    for _, e in ipairs(stage.e) do
                        local ni = #frame_state.bindings+1
                        frame_state.bindings[ni] = {e.d}
                        for _, name in ipairs(e.a) do bimap_write(frame_state.labels, "bl", ni, name) end end
                    return frame_state
                end,
                direct_snapshot = function (self, layer_id, frame_state) -- THIS IS RAW AUTHORITY THAT VOIDS SECURITY GUARANTEES
                    frame_state = frame_state or {labels = {lb={},bl={}}, bindings = {}} -- when provided, pours effects directly
                    for _,b in ipairs(self.layers[layer_id].c.ob) do
                        local ni = #frame_state.bindings+1
                        frame_state.bindings[ni] = {self.bindings[b].records[#self.layers]}
                        if type(self.labels.bl[b]) == "string" then
                            bimap_write(frame_state.labels, "bl", ni, self.labels.bl[b]) end end
                    return frame_state end,
                inner_snapshot = function (self) -- used in Frame, in order to track writes
                    return self:direct_snapshot(#self.layers)
                end,
                view_snapshot = function (self, outer)
                    local frame_state = {labels = {lb={},bl={}}, bindings = {}}
                    for i = 1, #self.relevance.dl - (outer and 1 or 0) do -- we still will be traversing every layer, so it's recomended that user shouldn't use it
                        self:direct_snapshot(i,frame_state)
                    end
                    return frame_state
                end,
                env_snapshot = function (self, outer) -- same as view_snapshot, but provides in depth trace of context changes layer by layer
                    -- table with Frame manifests that inherit from each other
                    -- though I think I can provide an interface for KES access through special resolves per layers, instead of doing all of this
                    -- THIS IS AN AUTHORITY FOR DEBUGGER, THIS VIOLATES SECURITY GUARANTEES
                end,
                log_bindings = function (self)
                    for b,d in pairs(self.bindings) do
                        io.write((self.labels.bl[b] or "<binding "..tostring(b)..">")..": "..tostring(b).."| ")
                        for l,_ in pairs(d.records) do
                            io.write(tostring(l)..",")
                        end
                        io.write("\n")
                        --pprint(d.records)
                    end
                end,
                log_layers = function (self)
                    print("==== KES State Info ====")
                    print("\tlayers (or curr layer ID): "..tostring(#self.layers) )
                    io.write("\trelavance: depth | layer = ")
                    pprint(self.relevance.dl)
                    io.write("\tisolations: order | depth = ")
                    pprint(self.isolations.od)
                end,
                check_integrity = function (self) -- unit test for KES, I think I'll need to improve it more, so others'll know why they blown off their foot
                    local db = self.bindings
                    local ls = self.labels
                    print("==== KES Integrity Info START ====")
                    for id,layer in pairs(self.layers) do
                        for o,b in ipairs(layer.c.ob) do
                            if (not db[b]) then print(string.format("missing %s binding (aka %s) at %d depth %d", b, tostring(ls.bl[b] or "<ANON>"), id, layer.d))
                            elseif (not db[b].order.lo[id]) then print(string.format("missing layer link of %s binding (aka %s) at %d depth %d", b, tostring(ls.bl[b] or "<ANON>"), id, layer.d)) end
                        end
                    end
                    local mdc = 0
                    for id,bind in pairs(db) do
                        mdc = mdc + 1
                        for l,e in pairs(bind.records) do
                            if (not self.layers[l]) then print(string.format("dangling %s binding (aka %s) at %d depth %s", bind, tostring(ls.bl[bind] or "<ANON>"), l, "???")) end
                        end
                    end
                    if (#db ~= mdc) then print(string.format("binding db have gaps")) end
                    print("==== KES Integrity Info END ====")
                end
                --binding_label_get = function (self, b) return self.labels.bl[b] end, -- Used by Frame to make label list. probably pe replaced by 'pop_layer' Frame return
            },
            ESC = { -- EScapee Continuation
                closure = nil,
                start = function(self, err_handler, fn, ...) -- I need to reference KES. the KES on it's own is already big enough, I'm not sure it belongs there, but I'm sure it should do layer unwinding
                    local lid = FLESH.KES:get_context()
                    local ok, result = pcall(fn, ...)
                    if ok then return result end
                    while lid < FLESH.KES:get_context() do FLESH.KES:pop_layer() end -- rework into checkpoint and revert system, currently it's slow performance wise
                    -- result is the error thrown; if it's a registered signal, call it
                    if self.closure == result then
                        self.closure = nil -- consume
                        return result() end -- call the callback (result itself)

                    if err_handler then -- not sure about the design
                        return err_handler(result) else
                        error(result, 0) end -- we let the real error crash it
                end,
                shift = function(self, closure)
                    self.closure = closure -- register as a signal, so pcall won't mastake it for closure
                    error(closure) -- drop the lua stack
                end,
            },
            --local_manifest = false, -- Label resolve optimization?
            do_action = function (self, action, lt, rt) -- make sure to remeber right: clause is case of protocol, action is the manifest about to be executed
                if not (action and lt) then return self.NegI.RootContext.gap end
                local r
                if self:intentcheck(self.NegI.RootContext.Artifact.state, action.protocol) then
                    return action.state.artifact(lt, rt) else
                    return self:dispatch(action, self.make.Frame({self = lt, arg = rt})) end
                --return r or self.NegI.RootContext.gap
            end,
            dispatch = function (self, lterm, rterm, protocol) -- needs debugging
                --print("dispatch start")
                if lterm == nil then error("FLESH:dispatch - got nil, expected Manifest") return end
                protocol = protocol or lterm.protocol -- protocol argument is optional and here only for convinience, so I don't have to recreate manifest with transformed protocols
                if protocol and next(protocol) then
                    if protocol.fork and not self.KES:has_resource(lterm) then -- this is explicit, so I'll leave it like this
                        lterm = self:do_action(protocol.fork, lterm)
                        self.KES:own_resource(lterm, manifest_reaper) -- TODO: need to know where to store `free` drivers that are shared by Resources (including the one in make.Manifest)
                    end
                    if rterm then
                        if protocol.can then -- both "can" and "ask" may not be fulfilled unlike "can" or "get" or abscense of protocol actions
                            --print("can?")
                            if self:intentcheck(self.NegI.RootContext.Label.state, rterm.protocol) then -- we use direct access, because this stuff will depend on furst record anyways
                                --if (not rterm.state) then pprint(rterm) end
                                --if rterm.state.eager then goto label_eager end -- TODO: eager label protocol or make `()` force call get (force inline?)
                                local p = protocol.can[rterm.state.query]
                                if p then return self.make.Manifest(p, lterm.state) end end end -- if we don't have action, we should fall down to `ask`
                        if protocol.ask then -- `ask` action exist solely for cases when Manifest need to handle arbitrary labels, like vector axis swizzling, field "modification" (the field might be abscent) and etc
                            --print("ask?")
                            if self:intentcheck(self.NegI.RootContext.Label.state, rterm.protocol) then
                                --if rterm.state.eager then goto label_eager end
                                self:do_action(protocol.ask, lterm, rterm) end end
                        --::label_eager::
                        if protocol.call then
                            --print("call?")
                            if rterm.protocol and rterm.protocol.get then rterm = self:dispatch(rterm, nil) end -- passive evaluation, because caller expect contents
                            return self:do_action(protocol.call, lterm, rterm) -- needs some standartization on how this should be passed around, don't like hardcoded "self" and "arg"
                        elseif protocol.get then -- fallback to underlying manifest for an answer
                            local fabk = self:do_action(protocol.get, lterm)
                            if protocol.wrap then -- wraps the end of negotiation
                                --print("get and wrap.")
                                local result = self:dispatch(fabk, rterm)
                                self:do_action(protocol.wrap, lterm) -- wrapping up
                                return result
                            else
                                --print("get.")
                                return self:dispatch(fabk, rterm)
                            end
                        else return self.make.Error("OPHANIM: FLESH:dispatch Error: rterm is outside of lterm protocol capability") end
                    elseif protocol.get and not protocol.wrap then -- if we have wrapping, then we handle it with care or something
                        --print("get explicit.")
                        if protocol.wrap then -- wraps the end of negotiation, do not forget about `lift` clause!
                            --print("... and wrap.")
                            local fabk = self:do_action(protocol.get, lterm)
                            self:do_action(protocol.wrap, lterm) -- wrapping up
                            return fabk
                        end
                        return self:do_action(protocol.get, lterm)
                    else return lterm end
                elseif rterm then return self.make.Error("OPHANIM: FLESH:dispatch Error: missing protocol")
                else return lterm end
            end,
            capcheck = function(self, protocol_m, manifest, callback) -- Even through fallbacks, is manifest implements this protocol?
                --print("--cch call")
                local return_result = function (match)
                    if callback then
                        if match then return callback(match) else return end else
                        return match end
                end

                if protocol_m.state == manifest.protocol then return return_result(manifest)
                elseif protocol_m.state and manifest.protocol then

                    local protopaths = {}

                    local scout
                    scout = function (intent, m, pp)
                        --print("----scouting")
                        local argp = m.protocol
                        -- early exits
                        if pp[string.format("%p", m.protocol)] then return return_result() end
                        pp[string.format("%p", m.protocol)] = true
                        if protocol_m.state == m.protocol then return return_result(m) end
                        if not (intent and next(intent)) then return return_result(m) end
                        if not (argp and next(argp)) then return return_result() end

                        local can_matches = {}
                        if (intent.can and intent.can ~= argp.can) then
                            if argp.can then
                                for c,a in pairs(intent.can) do
                                    if argp.can[c] ~= a then
                                        if argp.can[c] and argp.can[c].get then
                                           
                                        end
                                        can_matches[c] = a
                                    end -- we stick to simplicity for now
                                end
                            else
                                can_matches = intent.can
                            end
                        end

                        intent = {
                            can = (next(can_matches)) and can_matches,
                            ask = (intent.ask ~= argp.ask) and intent.ask,
                            call = (intent.call ~= argp.call) and intent.call,
                            --wrap = intent.wrap and ((intent.wrap.enter or argp.wrap.enter or intent.wrap.exit ~= argp.wrap.exit) and intent.wrap),
                            wrap = (intent.wrap ~= argp.wrap) and intent.wrap,
                            get = (intent.get ~= argp.get) and intent.get,
                        }
                        if next(intent) then
                            --if argp.wrap and argp.wrap.enter then -- what if the protocol we checking against also have `wrap`?
                            --    local r = scout(intent, self:do_action(argp.wrap.enter, m), pp)
                            --    if argp.wrap.exit then self:do_action(argp.wrap.exit, m) end
                            --    return r end
                            if argp.get then return scout(intent, self:do_action(argp.get, m), pp) end -- what if the protocol we checking against also have `get`?
                            --print("---exauhsted m")
                            return return_result()
                        else
                            --print("---exauhsted intent")
                            return return_result(m)
                        end
                    end

                    return scout({
                        can = protocol_m.state.can,
                        ask = protocol_m.state.ask,
                        call = protocol_m.state.call,
                        wrap = protocol_m.state.wrap, -- if protocol has this, then we are looking for proxy
                        get = protocol_m.state.get -- same here
                    }, manifest, protopaths)
                elseif protocol_m.state and not manifest.protocol then
                    --print("--exauhsted m")
                    return return_result()
                end
                --print("--identical")
                return return_result(manifest)
            end,
            intentcheck = function (self, p_template, p_checking) -- for backend
                if p_template == p_checking then return true
                elseif p_template and p_checking then
                    for i,e in pairs(p_template) do
                        if (p_checking[i] ~= e) then
                            return false end end
                    if p_template.can == p_checking.can then return true
                    elseif p_template.can and p_checking.can then
                        for i,e in pairs(p_template.can) do -- need deep `can` checks
                            if (p_checking.can[i] ~= e) then
                                return false end end
                end end
                return true
            end,
            --env methods
            reset = function (self) end, -- inits defaults and other stuff, I have no idea on what it should do because there is already `newstate`
        }

        -- Manifest state is visible only to self and the one that checked it against capability
        -- Manifest state only mutable if it belongs to current layer and belongs to self

        FLESH.make = {} -- Manifest constructors

        FLESH.make.thunks = {}
        FLESH.make.unthunk = function ()
            for _,e in ipairs(FLESH.make.thunks) do e() end
            FLESH.make.thunks = {} end
        FLESH.make.Manifest = function (protocol, state) -- protocols are still eager, but it's possible to do lazy clause access via "get" manifests (like quoted labels). here we just doing it via metatable because it's convinient, and I'm making a PoC, not final product yet
            local r = (function () -- I don't like to rewrite something that's already works, so we just hook to result
                local m = {protocol = protocol, state = state}
                
                if type(protocol) == "table" then return m
                elseif type(protocol) == "function" then
                    local ok, result = pcall(protocol) -- lazy dispatch
                
                    if ok then -- convinence
                        return {protocol = result, state = state}
                    else
                        local dummy = {}
                        local undummy = function ()
                            setmetatable(dummy,nil)
                            for k,v in pairs(m) do dummy[k] = v end
                            dummy.protocol = m.protocol()
                        end
                        FLESH.make.thunks[#FLESH.make.thunks+1] = undummy
                        setmetatable(dummy, {
                            __index = function (t,k) -- lazy fetch, becuase some Manifests rely on that
                                undummy()
                                return t[k] end,
                            __newindex = function (t,k,v) undummy(); t[k] = v end,
                            __len = function () return #m end })
                        return dummy end
                else error("protocol expected as function or table, got "..type(protocol), 2) end
            end)()
            FLESH.KES:own_resource(r, manifest_reaper) -- lua uses GC, so we can't do anything.
            return r
        end

        FLESH.NegI = {RootContext = {}} -- the NegI assets

        FLESH.NegI.RootContext.Artifact = FLESH.make.Manifest( -- Artifact for handling external authority
            {
                can = {
                    ["in"] = {call = "stub"},
                    ["="] = {can = {source = {call = "stub"}}}}},
            {
                can = {
                    reload = {get = "stub"},
                    introspect = {get = "stub"}}, -- can't decide on a name yet, should return ingridients for cooking the authority in question
                call = "stub"})
       
        local dcopy = function (t)
            -- I need to add function for explicit import/deep copy, because currently it's not sandboxed properly
            return t
        end

        local artifact_env = { -- it's an environment centered around debug tools and devlopment environment, so having all that stuff here is fine
            -- Lua Language Internals
            basic = basic,
            assert = assert, error = error, warn = warn,
            collectgarbage = collectgarbage,
            dofile = dofile, load = load, loadfile = loadfile,
            getmetatable = getmetatable, setmetatable = setmetatable,
            ipairs = ipairs, pairs = pairs,
            next = next, select = select, unpack = unpack or table.unpack,
            pcall = pcall, xpcall = xpcall,
            print = print,
            rawequal = rawequal, rawget = rawget, rawlen = rawlen, rawset = rawset,
            require = require,
            tonumber = tonumber, tostring = tostring,
            type = type,

            -- it's unlikely that those get modified. in some cases they might be abscent or not full
            table = dcopy(table),
            math = dcopy(math),
            string = dcopy(string),
            utf8 = dcopy(utf8),
            debug = dcopy(debug),
            coroutine = dcopy(coroutine),
            io = dcopy(io),
            os = dcopy(os),
            package = dcopy(package),
       
            -- The OPHANIM Substrate
            -- Artifacts MUST use this to interact with the system.
            FLESH = FLESH,

            -- temporarely here for debug purposes
            pprint = pprint,
            ldbg = ldbg,
        }

        FLESH.NegI.RootContext.Substrate = FLESH.make.Manifest({},{})

        FLESH.NegI.RootContext.HostContext = FLESH.make.Manifest(FLESH.NegI.RootContext.Substrate.state, artifact_env)

        FLESH.make.ArtifactLL = function (env, a0, a1, body, chunkname)
            chunkname = chunkname or "chunk"
            local chunk = string.format("return function(%s,%s)%s end", a0, a1, body)
            local a, e = load(chunk, "OPHANIM:"..chunkname, "t", env.state)
            if (e) then
                local error_p = FLESH.NegI.RootContext.Error
                if error_p then return FLESH.make.Manifest(
                    error_p.state, {desc = "Artifact: Failed to load "..chunkname.." due to host error: "..e})
                else print("in ```lua\n"..chunk.."\n```"); error("FLESH.make.Artifact - Artifact construction failed on NegI sys init due to host error:"..tostring(e), 2) end
            end
            local ok, result = pcall(a)
            local callable_result = (type(result) == "function") or (getmetatable(result).__call)
            if (not callable_result) then
                if (not callable_result and ok) then result = "provided code is not callable!" end
                local error_p = FLESH.NegI.RootContext.Error
                if error_p then return FLESH.make.Manifest(
                    error_p.state, {desc = "Artifact: Failed to load "..chunkname.." due to host error: "..result})
                else print("in ```lua\n"..chunk.."\n```"); error("FLESH.make.Artifact - Artifact construction failed on NegI sys init due to host error:"..tostring(result), 2) end
            end
            return FLESH.make.Manifest(FLESH.NegI.RootContext.Artifact.state, {
                    --chunk = chunk,
                    a0 = a0,
                    a1 = a1,
                    body = body,
                    chunkname = chunkname,
                    --mode = mode,
                    env = env, -- Substrate manifest
                    artifact = result})
        end

        FLESH.make.ArtifactCore = function (body, chunkname) return FLESH.make.ArtifactLL(FLESH.NegI.RootContext.HostContext, "self", "arg", body, chunkname) end

        --common between protocol manifests
        local capability_check = FLESH.make.ArtifactCore([[
            return FLESH.make.Number(FLESH:capcheck(self, arg))]], "`in` aka capcheck")
       
        FLESH.NegI.RootContext.Artifact.protocol.can["in"].call = capability_check
        FLESH.NegI.RootContext.Artifact.protocol.can["="].can["source"].call = FLESH.make.ArtifactCore([[
            local str_p = FLESH.NegI.RootContext.String
            local authority_recipie = FLESH:capcheck(str_p, arg, (function (m) return m end)) -- I have to hack my way in
            --if (match ~= nil) then FLESH:dispatch(match, nil, match.protocol.can.load) end
            if authority_recipie then
                return FLESH.make.ArtifactCore(authority_recipie.state, "NegI_Artifact") else
                return FLESH.make.Error("expected String, got something else") end
        ]], "Artifact can = can source call")
        --FLESH.NegI.RootContext.Artifact.protocol.can["="].can["bytecode"].call = FLESH.make.ArtifactCore([[
        --    local str_p = FLESH.NegI.RootContext.String
        --    local authority_recipie = FLESH:capcheck(str_p, arg, (function (m) return m end)) -- I have to hack my way in
        --    --if (match ~= nil) then FLESH:dispatch(match, nil, match.protocol.can.load) end
        --    if authority_recipie then
        --        return FLESH.make.ArtifactCore(authority_recipie.state, "NegI_Artifact") else
        --        return FLESH.make.Error("expected String, got something else") end
        --]], "Artifact can = can text call")
        FLESH.NegI.RootContext.Artifact.state.can.reload.get = FLESH.make.ArtifactCore([[
            return FLESH.make.Artifact(self.state.chunk, self.state.chunkname, self.state.mode, self.state.env) ]], "Artifact can reload")
        FLESH.NegI.RootContext.Artifact.state.can.introspect.get = FLESH.make.ArtifactCore([[ ]], "Artifact can intospect")
        FLESH.NegI.RootContext.Artifact.state.call = FLESH.make.ArtifactCore([[
            --ldbg(false)
            return self.state.artifact(
                FLESH.NegI.Intrinsics.frame_index(arg.state, 1),
                FLESH.NegI.Intrinsics.frame_index(arg.state, 2)
            ) ]], "Artifact call")

        FLESH.make.Frame = function (t)
            -- WARNING: the nested table is interface, but the content of it must be Manifests
            local s = {labels = {lb={},bl={}}, bindings = {}}
            --s.labels : BiMap<label: string, binding: number>
            --s.bindings : Array<bind: number, {parent: table, delta: number}|{delta: any}> -- for PoC it's enough, but I should later optimize it for memory, because inheriting lots of data would create lots of redundancy
            for k,v in pairs(t) do
                local ni = #s.bindings+1
                s.bindings[ni] = {v} -- we adding data not inheriting data, so there's no parent
                if type(k) == "string" then -- I don't have plans on introducing numeric keys, because bindings already have these
                    bimap_write(s.labels, "lb", k, ni) end end
            return FLESH.make.Manifest(FLESH.NegI.RootContext.Frame.state, s)
        end

        FLESH.make.Error = function (desc) return FLESH.make.Manifest(FLESH.NegI.RootContext.Error, {desc = desc}) end -- this one should hold more info than currently it is. Prefereably it should be able to store an Error chain, this will be a common occurence in NegI.

        FLESH.make.Number = function (val)
            return (({
                number = function (num) return FLESH.make.Manifest(FLESH.NegI.RootContext.Number.state, num) end,
                boolean = function (bool) return bool and FLESH.NegI.RootContext["true"] or FLESH.NegI.RootContext["false"] end
            })[type(val)] or (function (val) return FLESH.make.Error("invalid type (rework this error)") end))(val)
        end

        FLESH.make.String = function (val)
            return (type(val) == "string") and
                FLESH.make.Manifest(FLESH.NegI.RootContext.String.state, val) or
                FLESH.make.Error("invalid type (rework this error)")
        end

        -- no implicit conversions, this is only between this specific implementation
        local make_trans_op = function (op)
            return FLESH.make.ArtifactCore([[
                if (FLESH:capcheck({state = self.protocol},arg)) then -- 2nd value might have different protocol, I think I'll need to rework this into lua general value protocol check or something.
                    return FLESH:import(self.state ]]..op..[[ arg.state)
                else
                    return -- Error manifest
                end
            ]], op.." operator call")
        end
        local make_trans = function (trans)
            return FLESH.make.ArtifactCore([[
                return FLESH:import(]]..trans..[[(self.state))
            ]], trans.." uniarg call")
        end
        local make_host_res_init = function (host_type)
            return FLESH.make.ArtifactCore([[
                -- wrap host resource manifest
                if (type(arg) == "]]..host_type..[[") then return FLESH.make.Manifest(self.state, arg) end
                if (FLESH:capcheck(self,arg)) then return arg end -- literal uses same protocol, so we just wraping
                return -- Error manifest
            ]])
        end

        FLESH.NegI.Assets = { -- intermediate manifests that shouldn't be visible to the end user
            Breaker = FLESH.make.ArtifactCore([[
                FLESH.ESC:shift(function ()
                    return FLESH:dispatch(self.state, arg)
                end)
            ]], "Breaker"), -- not sure about clause
            Lift = FLESH.make.ArtifactCore([[
                local h = self
                if FLESH.KES:has_resource(h) then -- prevent halt on cyclic dependencies
                    FLESH.KES:lift_resource(h)
                    local res = h and h.protocol and h.protocol.res
                    if res then FLESH:do_action(res, h, FLESH.NegI.Assets.Lift) end
                end
                ]], "Lift") -- res passes the resource handles via temporary Resource manifest
        }

        FLESH.NegI.Intrinsics = { -- shared code between Manifests for optimization reasons, because these are tightly coupled anyways
            merge_protocols = function (p_base, p_inject) -- injection do not overwrite base clauses
                local protocol = {
                    can = (p_base.can or p_inject.can) and {} or nil,
                    ask = p_base.ask or p_inject.ask,
                    call = p_base.call or p_inject.call,
                    get = p_base.get or p_inject.get,
                    wrap = p_base.wrap or p_inject.wrap,
                    fork = p_base.fork or p_inject.fork,
                    lift = p_base.lift or p_inject.lift,
                    res = p_base.res or p_inject.res}

                for c,p in pairs(p_base.can or {}) do protocol.can[c] = p end
                for c,p in pairs(p_inject.can or {}) do protocol.can[c] = protocol.can[c] or p end

                return protocol
            end,
            frame_index = function (frame_state, query, skip_cache)
                --pprint(frame_state.bindings)
                local label
                if type(query) ~= "number" and type(query) ~= "string" then error("expected number or string", 2) end
                if type(query) == "string" then
                    label = query 
                    query = frame_state.labels.lb[query] 
                end
                if query then 
                    local value = frame_state.bindings[query] -- TODO: needs rework - I need to keep track of failed attempts (missing breadcrumb of nils)
                    if value then return value[1] end end -- [1] stores known search result
                if frame_state.parent then -- major parent, this points to state, not binding table!
                    local r = frame_index(frame_state.parent, label, true)
                    if skip_cache then FLESH.NegI.Intrinsics.frame_setex(frame_state, label, query, r) end
                    return r end
            end,
            frame_append = function (frame_state, data)
                local ni = #frame_state.bindings + 1
                frame_state.bindings[ni] = {data}
                frame_state.length = frame_state.length + 1
                return ni
            end,
            frame_set = function (frame_state, query, data) -- TODO: add counters for last index and, unique query entries and overall item amount 
                if type(query) ~= "number" and type(query) ~= "string" and query ~= nil then error("expected number or string or nil at #2 arg", 2) end
                if type(query) == "string" then
                    local label = query
                    query = frame_state.labels.lb[query]
                    if not query then 
                        query = FLESH.NegI.Intrinsics.frame_append(frame_state, data)
                        bimap_write(frame_state.labels, "lb", label, query)
                        return query end
                else 
                    if not query then query = #frame_state.bindings+1 end
                    if not (frame_state.bindings[query] and not frame_state.bindings[query][1]) then frame_state.length = frame_state.length + 1 end
                    frame_state.bindings[query] = {data}
                    return query
                end
            end,
            frame_setex = function (frame_state, label, binding, data)
                --if type(label) ~= "string" then error("expected string at #2 arg", 2) end
                binding = binding or frame_state.labels.lb[label] or #frame_state.bindings+1
                if type(binding) ~= "number" then error("expected number at #3 arg", 2) end
                if type(label) == "string" then
                    bimap_write(frame_state.labels, "lb", label, binding) end -- move the label to new binding
                frame_state.bindings[binding] = {data}
            end,
            frame_label = function (frame_state, label, binding)
                if type(label) == "string" then
                    bimap_write(frame_state.labels, "lb", label, binding) end -- do note that Frame can't have more labels per binding, unlike context layers
            end,
            frame_getlabel = function (frame_state, label, binding)
                return frame_state.labels.bl[binding]
            end,
            the_passer = function (self, arg) return arg end
        }

        FLESH.NegI.RootContext = { -- this is the core shared interface (or "corelib" if you'd like to call it like that), the abstract foundation for any logic that will come next. TODO: I need to move NegI protocols inside of it
            Resource = FLESH.make.Manifest({ -- should represent state during introspection, to make it hostile
                ["in"] = {call = capability_check}},{
                can = { -- lua allows importing, but compiled/static languages have a possibility of not working out like that
                    import = {get = FLESH.make.ArtifactCore("return FLESH:import(self.state)", "Resource can import")}}
            },{
               
            }),
            Substrate = FLESH.NegI.RootContext.Substrate,
            HostContext = FLESH.NegI.RootContext.HostContext,
            Artifact = FLESH.NegI.RootContext.Artifact, -- Host authority descriptor, seek definition before this
            Error = FLESH.make.Manifest({ -- Error is always as valua
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[
                    ]])}
                }
            },{
                can = {
                    name = {get = FLESH.make.ArtifactCore([[ ]])},
                    desc = {get = FLESH.make.ArtifactCore([[
                        return FLESH.make.String(tostring(self.state.desc))
                    ]])},
                    caller = {get = FLESH.make.ArtifactCore([[ ]])},
                    trace = {get = FLESH.make.ArtifactCore([[ ]])},
                },    
            }),
            Token = FLESH.make.Manifest({["in"] = {call = capability_check}},{ -- adds metainfo that's used by `Error`s, so you can read the exact place of where your code failed
                can = {
                    token = {can = {
                        root = {get = FLESH.make.ArtifactCore([[ ]])}, -- references root Token from where it is
                        parent = {get = FLESH.make.ArtifactCore([[ ]])}, -- return parent Token (probably won't add this, because I don't store that)
                        element = {get = FLESH.make.ArtifactCore([[ ]])}, -- text representation of Token
                        id = {get = nil}, -- it's id (probably will remove it)
                        position = {get = nil}, -- position relative to root Token text representation
                        content = {get = nil}, -- return Frame with it's child Tokens (probably won't add this, because I store that in opaque non-uniform states)
                    }}
                },
                get = FLESH.make.ArtifactCore([[ return self.state.token ]]), -- fallback to standard token operation
            }),
            Manifest = FLESH.make.Manifest({ -- Protocol for directly constructing Manifests
                can = {
                    ["in"] = {call = capability_check}, -- capability_check is shared artifact
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])},
                    },
                },{}),-- thats "any" type, there's nothing to check, because everything is a Manifest
            ManifestMeta = FLESH.make.Manifest({ -- Protocol for Manifest Inspection/Reflection
                can = {
                    ["in"] = {call = capability_check}, -- capability_check is shared artifact
                    ["="] = {call = FLESH.make.ArtifactCore([[ return FLESH.make.Manifest(self.state, arg) ]])}, -- we don't need checks, everything is a manifest
                    },
                },{
                    can = {
                        ["=="] = {call = FLESH.make.ArtifactCore([[
                            return FLESH.make.Number(rawequal(self.state.protocol, arg.protocol) == true) and -- we check protocol and state separately, because table that holds these, don't provide the identity
                                FLESH.make.Number(rawequal(self.state.state, arg.state) == true) -- self.state have arg from `=` with both protocol and state
                        ]], "ManifestMeta can == call")},
                        protocol = {get = FLESH.make.ArtifactCore([[ return FLESH.make.Manifest( FLESH.NegI.RootContext.Protocol.state , self.state.protocol ) ]], "ManifestMeta can protocol get")},
                        state = {get = FLESH.make.ArtifactCore([[ return FLESH.make.Manifest(FLESH.NegI.RootContext.Resource.state, self.state.state) ]], "ManifestMeta can state get")}, -- it is opaque, so Resource it is
                        back = {get = FLESH.make.ArtifactCore([[ return self.state ]], "ManifestMeta can back get")}, -- not sure about it
                    }
                }),-- that's more like you pulled up an inspection tool, and this tool gives you this
            Protocol = FLESH.make.Manifest({ -- Protocol for new Protocols
                    can = {
                        of = {call = FLESH.make.ArtifactCore([[ ]])}, -- will return the protocol of some Manifest that could be used to check other Manifests
                        ["in"] = {call = capability_check}, -- capability_check is shared artifact
                        ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                    },
                    call = FLESH.make.ArtifactCore([[ ]]), -- artifact for creating new protocol manifests
                },{
                    ["in"] = capability_check
                }),
            ["//"] = FLESH.make.Manifest({
                get = FLESH.make.ArtifactCore(" return { protocol = { get = FLESH.make.ArtifactCore(\" return arg \")}}")},{}),
            pass = FLESH.make.Manifest({ -- TODO: explicitly ends Sequence with appropriate data. monad where first is to where and 2nd is data
                call = FLESH.make.ArtifactCore([[ -- not sure about the clause, so I'll leave it like this
                    return FLESH.make.Manifest({call = FLESH.NegI.Assets.Breaker},arg)
                ]])
            },{}),
            ["false"] = FLESH.make.Manifest(function () return FLESH.NegI.RootContext.Number.state end,0), -- sugar
            ["true"] = FLESH.make.Manifest(function () return FLESH.NegI.RootContext.Number.state end,1), -- sugar
            gap = FLESH.make.Manifest({},{}), -- it's fine, that's how it should be
            Number = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }},{
                    can = {
                        ["+"] = {call = FLESH.make.ArtifactCore([[
                            local num_p = FLESH.NegI.RootContext.Number
                            return FLESH:capcheck(num_p, arg, (function (match) -- rework as deep intent checks
                                return FLESH.make.Number(self.state + match.state)
                            end)) or FLESH.make.Error("Number can + call: expected number, got something else")
                        ]], "Number can + call")},
                        ["-"] = {call = FLESH.make.ArtifactCore([[
                            local num_p = FLESH.NegI.RootContext.Number
                            return FLESH:capcheck(num_p, arg, (function (match)
                                return FLESH.make.Number(self.state - match.state)
                            end)) or FLESH.make.Error("Number can - call: expected number, got something else")
                        ]], "Number can - call")},
                        ["*"] = {call = FLESH.make.ArtifactCore([[
                            local num_p = FLESH.NegI.RootContext.Number
                            return FLESH:capcheck(num_p, arg, (function (match)
                                return FLESH.make.Number(self.state * match.state)
                            end)) or FLESH.make.Error("Number can * call: expected number, got something else")
                        ]], "Number can * call")},
                        ["/"] = {call = FLESH.make.ArtifactCore([[
                            local num_p = FLESH.NegI.RootContext.Number
                            return FLESH:capcheck(num_p, arg, (function (match)
                                return FLESH.make.Number(self.state / match.state)
                            end)) or FLESH.make.Error("Number can / call: expected number, got something else")
                        ]], "Number can / call")},
                        ["<>"] = {call = FLESH.make.ArtifactCore([[
                            local num_p = FLESH.NegI.RootContext.Number
                            return FLESH:capcheck(num_p, arg, (function (match)
                                return FLESH.make.Number(
                                    self.state == match.state and 0 or
                                    self.state < match.state and 1 or -1)
                            end)) or FLESH.make.Error("Number can <> call: expected number, got something else")
                        ]], "Number can <> call")},
                        
                    },
                   
                }), -- need to make generic host agnostic number representation (maybe even Rational out of 2 BigIntegers or just BigInteger to not conflate these 2 for the compilation process)
            String = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }},{
                    can = {
                        length = {get = FLESH.make.ArtifactCore("return FLESH.make.Number(#self.state)")}
                    },
                    call = FLESH.make.ArtifactCore([[
                        local num_p = FLESH.NegI.RootContext.Number
                        local frame_p = FLESH.NegI.RootContext.Frame
                        if (FLESH:capcheck(num_p, arg)) then
                            return FLESH.make.String(self.state:sub(arg.state,arg.state))
                        elseif (FLESH:capcheck(frame_p, arg)) then -- slicing in python style
                            local s_start = FLESH.NegI.Intrinsics.frame_index(arg.state, "start") or FLESH.NegI.Intrinsics.frame_index(arg.state, 1)
                            local s_end = FLESH.NegI.Intrinsics.frame_index(arg.state, "end") or FLESH.NegI.Intrinsics.frame_index(arg.state, 2)
                            if (s_start) then if (not FLESH:capcheck(num_p, s_start)) then
                                return FLESH.make.Error("String call: expected number in frame at `start` or 1, got something else")
                            end else
                                return FLESH.make.Error("String call: expected number in frame at `start` or 1, got something else")
                            end
                            if (s_end) then if (not FLESH:capcheck(num_p, s_end)) then
                                return FLESH.make.Error("String call: expected number or gap in frame at `end` or 2, got something else")
                            end end
                            return FLESH.make.String(self.state:sub(s_start,s_end or s_start))
                        end
                        return FLESH.make.Error("String call: expected frame or number, got something else")
                    ]], "String call"),
                    res = FLESH.make.ArtifactCore([[

                    ]])
                }), -- some hosts might have to emulate this
            --Slot = FLESH.make.Manifest({ -- interface for Label and FrameSlot
            --    ["in"] = {call = capability_check},
            --    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
            --},{
            --    can = {
            --        [":"] = {
            --            get = FLESH.make.ArtifactCore([[
            --                FLESH.KES:stage_alias(self.state.query)
            --                return FLESH.NegI.RootContext.gap ]]),
            --            call = FLESH.make.ArtifactCore([[
            --                FLESH.KES:stage_alias(self.state.query)
            --                return arg ]])},
            --    },
            --    get = FLESH.make.ArtifactCore([[
            --        local 
            --        return FLESH:do_action(self.state.place) or FLESH.NegI.RootContext.gap
            --    ]], "Slot get")
            --})
            Label = FLESH.make.Manifest({ -- it's job is to represent a get query from KES to load manifests
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }},{
                can = {
                    [":"] = {
                        get = FLESH.make.ArtifactCore([[
                            FLESH.KES:stage_alias(self.state.query)
                            return FLESH.NegI.RootContext.gap ]]),
                        call = FLESH.make.ArtifactCore([[
                            FLESH.KES:stage_alias(self.state.query)
                            return arg ]])},
                    query = {
                        get = FLESH.make.ArtifactCore([[
                            return FLESH.make.String(self.state.query)
                        ]], "Label can query get")
                    }
                },
                get = FLESH.make.ArtifactCore([[
                    local m, _ = FLESH.KES:resolve(self.state.query)
                    return m or FLESH.NegI.RootContext.gap
                ]], "Label get")
            }),
            Frame = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }},{
                    fork = FLESH.make.ArtifactCore([[
                        local r = FLESH.make.Manifest(self.protocol, {labels = {lb={},bl={}}, bindings = {}})
                        r.state.parent = self.state
                        r.state.length = self.state.length
                        --if r.state.length < 64 then
                        --    for k,v in pairs(self.state.bindings) do
                        --
                        --    end
                        --end
                        return r
                    ]], "Frame fork"),
                    can = {
                        ["++"] = {call = FLESH.make.ArtifactCore([[
                            FLESH.NegI.Intrinsics.frame_append(self.state, arg)
                        ]], "Frame can ++(aka item append)")},
                        ["+"] = {call = FLESH.make.ArtifactCore([[
                            
                        ]], "Frame can +(aka join)")}, 
                        --["*"] = {call = FLESH.make.ArtifactCore([[ ]])},
                        load = {get = FLESH.make.ArtifactCore([[
                            local labels, bindings = self.state.labels, self.state.bindings
                            for b,e in pairs(bindings) do
                                local sid = FLESH.KES:stage_entry(e[1])
                                --pprint(self.state)
                                --print("load: "..(labels.bl[b] or "<anonymic "..b..">"))
                                if (labels.bl[b]) then FLESH.KES:stage_alias(labels.bl[b], sid) end -- sometimes, user will want to load Frame inside a Frame.
                            end
                            return FLESH.NegI.RootContext.gap
                        ]], "Frame can load get")},
                        ["."] = {ask = FLESH.make.ArtifactCore([[
                            return FLESH.NegI.Intrinsics.frame_index(self.state, arg.state.query) or FLESH.NegI.RootContext.gap 
                        ]], "Frame can . ask")},
                        --["/"] = {call = FLESH.make.ArtifactCore([[
                        --    --self.state.labels
                        --]], "Frame can / call")},
                        map = {call = FLESH.make.ArtifactCore([[ ]])},
                        concetrate = {get = FLESH.make.ArtifactCore([[ ]])},
                    },
                    call = FLESH.make.ArtifactCore([[
                        local num_p = FLESH.NegI.RootContext.Number
                        local str_p = FLESH.NegI.RootContext.String
                        if (FLESH:capcheck(num_p, arg)) then
                            return FLESH.NegI.Intrinsics.frame_index(self.state, arg.state + 1) or FLESH.NegI.RootContext.gap
                        elseif (FLESH:capcheck(str_p, arg)) then
                            return FLESH.NegI.Intrinsics.frame_index(self.state, arg.state) or FLESH.NegI.RootContext.gap
                        elseif (FLESH:capcheck({state = self.protocol}, arg) and arg) then -- slicing in python style
                           
                        else

                        end
                        return FLESH.make.Error("Frame call: expected string or number, got something else")
                    ]], "Frame call"), -- indexing with splicing
                    res = FLESH.make.ArtifactCore([[
                        for _,e in pairs(self.state.bindings) do FLESH:do_action(arg, e[1]) end
                    ]], "Frame res") -- I think giving it nice wrapping wastes memory, if user needs, they'll do that via visitor
            }),
            Sequence = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }},{
                    can = {
                        prods = {get = FLESH.make.ArtifactCore([[ ]])}, -- in order to get raw data, @ must be used
                        creturn = {get = FLESH.make.ArtifactCore([[ ]])}, -- in order to get raw data, @ must be used
                        introspect = {get = FLESH.make.ArtifactCore([[ ]])}
                    },
                    call = FLESH.make.ArtifactCore([[
                        local prods = self.state.prods
                        local frame_p = FLESH.NegI.RootContext.Frame
                        --local load_cmd = FLESH:dispatch(arg, FLESH.make.Manifest(FLESH.NegI.RootContext.Label.state, {query = "load"}))
                        --if load_cmd == frame_p.state.can.load then FLESH:dispatch(load_cmd) end -- technically this is a correct way, but it doesn't work for now, so...
                        local match = FLESH:capcheck(frame_p, arg, (function (m) return m end)) -- I have to hack my way in
                        FLESH.KES:push_layer(self.state.ldepth, self.state.isolate)
                        if (match ~= nil) then 
                            FLESH:dispatch(match, nil, match.protocol.can.load)
                            FLESH.KES:stage_commit(function (q,m) return FLESH.KES:write_entry(q,m) end) end
                        local r = FLESH.ESC:start(nil, (function ()
                        for i,e in ipairs(prods) do
                            e = e or FLESH.NegI.RootContext.gap
                            e = FLESH:dispatch(e); e = e or FLESH.NegI.RootContext.gap -- evaluation
                            e = FLESH:dispatch(e) -- get
                            FLESH.KES:stage_fill_reserve(e)
                            FLESH.KES:stage_commit(function (q,m) return FLESH.KES:write_entry(q,m) end) end
                        return self.state.creturn and FLESH:dispatch(self.state.creturn) -- I made sure that parser now gives AST.GAP, instead of nil, so if we get an error, it won't be because of parser
                        end))
                        FLESH.KES:pop_layer(r)
                        return r or FLESH.NegI.RootContext.gap
                    ]], "Sequence call"),
                    lift = FLESH.make.ArtifactCore([[ self.state.ldepth = math.min(self.state.ldepth, FLESH.KES:get_depth()) ]], "Sequnece lift")
            }),
            Quote = FLESH.make.Manifest({ -- aka {} or dynamic (because it will shift parent within isolation)
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }
            },{
                get = FLESH.make.ArtifactCore([[
                    FLESH.KES:push_layer(FLESH.KES:unquote_parent(self.state.parent), self.state.contain)
                    return self.state.content or FLESH.NegI.RootContext.gap
                ]], "Quote get"),
                wrap = FLESH.make.ArtifactCore([[
                    FLESH.KES:pop_layer(self.state.content)
                    ]], "Quote wrap"),
                lift = FLESH.make.ArtifactCore([[ self.state.parent = math.min(self.state.parent, FLESH.KES:get_depth()) ]], "Quote lift")
            }),
            Eager = FLESH.make.Manifest({ -- aka (), forces first Manifest to evaluate through get
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }
            },{
                get = FLESH.make.ArtifactCore([[return FLESH:dispatch(self.state.content) or FLESH.NegI.RootContext.gap]], "Eager get"),
            }),
            Negotiation = FLESH.make.Manifest({ -- aka jusxtaposition
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
                }},{
                    get = FLESH.make.ArtifactCore([[
                        -- resolve terms: we hold references in state, not data
                        local lt = self.state.lterm
                        local rt = self.state.rterm or FLESH.NegI.RootContext.gap

                        return FLESH:dispatch(lt, rt) or FLESH.NegI.RootContext.gap
                    ]], "Negotiation get")
            }),
            Gate = FLESH.make.Manifest({
                ["in"] = {call = capability_check},
                ["="] = {call = FLESH.make.ArtifactCore([[ ]])} -- this lil guy expects Mold
            },{

            }),
            Mold = FLESH.make.Manifest({ -- it checks if within specific labels manifests sitisfy protocol checks. (Should it do deep checks? I think doing shallow ones is ok and keeps it safe from halting?)
                ["in"] = {call = capability_check},
                ["="] = {call = FLESH.make.ArtifactCore([[ ]])}
            },{
                can = {
                    cast = {call = FLESH.make.ArtifactCore([[
                        
                    ]], "Mold can cast call")},
                },
                call = FLESH.make.ArtifactCore([[

                ]]), -- we check the environment with this one
            }),
            context = FLESH.make.Manifest({
                can = {
                    inner = {
                        can = {
                            has = {ask = FLESH.make.ArtifactCore([[
                                return FLESH.KES:has_resource(arg.query) and FLESH.NegI.RootContext["true"] or FLESH.NegI.RootContext["false"]
                            ]], "context can inner can has call")}},
                        get = FLESH.make.ArtifactCore([[ return FLESH.make.Manifest(FLESH.NegI.RootContext.Frame.state, FLESH.KES:inner_snapshot()) ]], "context can inner get")},
                    outer = {get = FLESH.make.ArtifactCore([[ return FLESH.make.Manifest(FLESH.NegI.RootContext.Frame.state, FLESH.KES:view_snapshot(true)) ]], "context can outer get")},
                    full = {get = FLESH.make.ArtifactCore([[ return FLESH.make.Manifest(FLESH.NegI.RootContext.Frame.state, FLESH.KES:view_snapshot()) ]], "context can full get")},
                }
            },{}),
            -- TODO: in order to finish Parser, Depictor, Mount, Gate: I need to finish Frame and Mold first
            Parser = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])} -- make one given the list of Manifest nodes
                }
            },{
                can = {
                    nodes = {get = FLESH.make.ArtifactCore([[ ]])} -- get Frame with responsible manifests
                },
                call = FLESH.make.ArtifactCore([[ ]]) -- parse and return installer object (due to multithreading, we need to link the namespaces of parsed object and existing runtime)
            }),
            Depictor = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[ ]])} -- make one given the list of Manifest nodes
                }
            },{
                can = {
                    depictions = {get = FLESH.make.ArtifactCore([[ ]])} -- get Frame with depictions
                },
                call = FLESH.make.ArtifactCore([[ ]])
            }),
            Mount = FLESH.make.Manifest({
                can = {
                    ["in"] = {call = capability_check},
                    ["="] = {call = FLESH.make.ArtifactCore([[
                       
                    ]], "Mount can = call")},
                },
                call = FLESH.make.ArtifactCore([[
                    -- here we expect frame with driver
                ]], "Mount call")
            },{
                can = {
                    -- should I just make another can case that contain all those different options for path building?
                    ["^"] = {get = FLESH.make.ArtifactCore([[
                        local lsub = FLESH.make.Manifest(self.protocol, {driver = self.state.driver})
                        for i,e in ipairs(self.state.path) do lsub.state.path[i] = e end
                        lsub.state.path[#lsub.state.path] = nil
                        return lsub
                    ]])},
                    ["."] = {ask = FLESH.make.ArtifactCore([[
                        local lsub = FLESH.make.Manifest(self.protocol, {driver = self.state.driver})
                        for i,e in ipairs(self.state.path) do lsub.state.path[i] = e end
                        lsub.state.path[#lsub.state.path+1] = arg.state.query
                        return lsub
                    ]], "Mount can . ask")},
                    ["/"] = {call = FLESH.make.ArtifactCore([[
                        local str_p = FLESH.NegI.RootContext.String
                        local match = FLESH:capcheck(str_p, arg, (function (m) return m end))
                        if (match == nil) then return FLESH.make.Error("Expected string, got something else") end

                        local lsub = FLESH.make.Manifest(self.protocol, {driver = self.state.driver})

                        --if (arg.state == "..") then
                        --    -- go up the directory
                        --    return FLESH.make.Manifest(self.protocol, nsta)
                        --end

                        for i,e in ipairs(self.state.path) do lsub.state.path[i] = e end
                        lsub.state.path[#lsub.state.path+1] = arg.state
                        return lsub
                    ]], "Mount can / call")},
                    meta = {},
                    pull = {get = FLESH.make.ArtifactCore([[
                        return FLESH:do_action(self.state.driver.pull, self)
                    ]])},
                    push = {call = FLESH.make.ArtifactCore([[
                        local str_p = FLESH.NegI.RootContext.String
                        local match = FLESH:capcheck(str_p, arg, (function (m) return m end))
                        if (match == nil) then return FLESH.make.Error("Expected string, got something else") end

                        return FLESH:do_action(self.state.driver.push, self, arg)
                    ]])},
                }
            }),
            --mount_virtual = FLESH.make.Frame({ -- virtual storage mount driver
            --    pull = FLESH.make.ArtifactCore([[
            --        
            --    ]]),
            --    push = FLESH.make.ArtifactCore([[
            --        
            --    ]]),
            --}),
            manifest_reaper = FLESH.make.ArtifactCore([[]], "Manifest reaper"), -- lua uses GC, so we just leak it, hoping that GC will pick it up
        }
 
        manifest_reaper.protocol = FLESH.NegI.RootContext.manifest_reaper.protocol
        manifest_reaper.state = FLESH.NegI.RootContext.manifest_reaper.state

        FLESH.NegI.parse = (function ()
            -- Parser assets and constants
            local TOKENTYPE = { -- enumeration for tokenizer
                NUMBER = 0,
                STRING = 1,
                LABEL = 2,
                MEMBRANE_OPEN = 3,
                MEMBRANE_CLOSE = 4,
                FINISH_ELEMENT = 5,
                FINISH_ACTION = 6
            }

            local tokenname = table_invert(TOKENTYPE)

            local AST_METADATA = function (node, pos)
                return FLESH.make.Manifest(FLESH.NegI.Token.state,{})
            end

            local framecr_p = {get = FLESH.make.ArtifactCore([[
                            local items = self.state.items
                            local labels = table.create and {lb=table.create(0,#items),bl=table.create(0,#items)} or {lb={},bl={}}
                            local frame_state = {labels = labels, bindings = {}, length = 0}
                            local loader = function ()
                                for i,e in ipairs(items) do
                                    local ststs = FLESH.KES:stage_staged() -- we need to check if there is a `load`, couldn't come up with a better way
                                    e = FLESH:dispatch(e); e = e or FLESH.NegI.RootContext.gap -- evaluate
                                    e = FLESH:dispatch(e) -- get
                                    if FLESH.KES:stage_reserved() then
                                        FLESH.KES:stage_fill_reserve(e) else
                                        if ststs == FLESH.KES:stage_staged() then FLESH.KES:stage_entry(e) end end end
                                --return FLESH.KES:stage_snapshot()
                            end

                            if (self.state.capture) then
                                FLESH.KES:stage_push()
                                loader()
                                FLESH.KES:stage_commit(function (q,m) return FLESH.NegI.Intrinsics.frame_set(frame_state, q, m) end)
                                FLESH.KES:stage_pop()
                                return FLESH.make.Manifest(FLESH.NegI.RootContext.Frame.state, frame_state)
                            else
                                loader()
                            end
                        ]], "FrameCreate get")}

            local seqcr_p = {get = FLESH.make.ArtifactCore([[
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.Sequence.state, {
                        prods = self.state.prods,
                        creturn = self.state.creturn,
                        isolate = self.state.isolate,
                        ldepth = FLESH.KES:get_depth()
                    })
                ]], "SequenceCreate get")}

            local quotecr_p = {get = FLESH.make.ArtifactCore([[
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.Quote.state, {
                        parent = FLESH.KES:get_depth(),
                        contain = self.state.isolate,
                        quoted = true,
                        content = self.state.content})
                ]], "QuoteCreate get")}

            -- Internal AST node creators (for parser output, I should also softcode this for evaluation reinterpretation)
            local AST = { -- refactoring the Sequence generator for parser
                GAP = function ()
                    --print("e_gap")
                    return FLESH.NegI.RootContext.gap -- we don't have anything on here
                end,
                NUMBER = function (value)
                    --print("e_number")
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.Number.state, value) end,
                STRING = function (value)
                    --print("e_string")
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.String.state, value) end,
                LABEL = function (query)
                    --print("e_label")
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.Label.state, {query = query}) end,
                FRAME = function (items) -- this one isn't a frame, but a frame constructor, that creates environment for writing, like Sequence
                    --print("e_frame")
                    return FLESH.make.Manifest(framecr_p, {items = items, capture = false}) end,
                SEQUENCE = function (prods, creturn) -- Sequence holds quoted stuff, but we still doing initialization, because Sequence need to know it's ground
                    --print("e_sequence")
                    return FLESH.make.Manifest(seqcr_p, {prods = prods, creturn = creturn, isolate = false}) end,
                QUOTE = function (content)
                    --print("e_quote")
                    return FLESH.make.Manifest(quotecr_p, {content = content, isolate = false}) end,
                EAGER = function (content)
                    --print("e_quote")
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.Eager.state, {content = content}) end,
                NEGOTIATION = function (lterm, rterm) -- evaluation units
                    --print("e_negotiation")
                    return FLESH.make.Manifest(FLESH.NegI.RootContext.Negotiation.state, {lterm = lterm, rterm = rterm}) end,
            }

            -- Internal: Recursive descent parsers (one per non-terminal)
            local parse_term, parse_negotiation, parse_product, parse_sequence

            parse_term = function(tokens, pos)
                local tok
                if pos <= #tokens then
                    tok = tokens[pos]
                    if tok.type == TOKENTYPE.MEMBRANE_OPEN then -- handle membrane: contain | quote | make
                        local kind = tok.value
                        local seq, pos = parse_sequence(tokens, pos + 1)
                        local concl = tokens[pos]
                        if (concl == nil) then -- TODO: make this mess unified, there are a lot of repetition
                            error(
                                "parse_term ERROR: Expected membrane_close '"..
                                string.sub("]})",tok.value,tok.value)..
                                "', but got nothing. Membrane begins "..
                                " at line:"..tostring(tok.at.line)..
                                ", char:"..tostring(tok.at.char), 2)
                        elseif (concl.type ~= TOKENTYPE.MEMBRANE_CLOSE) then
                            error(
                                "parse_term ERROR: Expected membrane_close for some reason (probably parser bug, because it's implicitly checked), but got '"..
                                tokenname[concl.type]..
                                "' at line:"..tostring(concl.at.line)..
                                ", char:"..tostring(concl.at.char), 2)
                        elseif (concl.value ~= kind) then
                            error(
                                "parse_term ERROR: Bracket missmatch. Forgot to open with '"..
                                string.sub("[{(",concl.value,concl.value)..
                                "' membrane? Expected this membrane to close with '"..
                                string.sub("]})",tok.value,tok.value)..
                                "' at line:"..tostring(concl.at.line)..
                                ", char:"..tostring(concl.at.char), 2)
                        end
                        if (seq == nil) then seq = AST.GAP() end -- state "nothingness" explicitly
                        ({
                            function () end,
                            function () seq = AST.QUOTE(seq) end,
                            function ()
                                if (seq.protocol == seqcr_p) then seq.state.isolate = true
                                elseif (seq.protocol == quotecr_p) then seq.state.isolate = true
                                elseif (seq.protocol == framecr_p) then seq.state.capture = true end
                                --elseif (seq.protocol == FLESH.NegI.RootContext.Label.state) then seq.state.eager = true end -- this needs more general way, not just this
                                seq = AST.EAGER(seq)
                            end
                        })[kind]()
                        return seq, pos + 1
                        --return AST.QUOTE(seq), pos + 1
                    elseif tok.type == TOKENTYPE.NUMBER then -- handle NUMBER
                        return AST.NUMBER(tok.value), pos + 1
                    elseif tok.type == TOKENTYPE.STRING then -- handle ESCAPED_STRING
                        return AST.STRING(tok.value), pos + 1
                    elseif tok.type == TOKENTYPE.LABEL then -- handle label
                        return AST.LABEL(tok.value), pos + 1
                    elseif -- handle gap
                        -- the code below generates ast_gap, to help tracking gaps inside sequences or frames
                        -- we can throw gap only if expeted term terminated by one of those 2 tokens
                        tok.type == TOKENTYPE.FINISH_ELEMENT or
                        tok.type == TOKENTYPE.FINISH_ACTION then
                        return AST.GAP(), pos
                    end
                end
                -- this could happen in cases like `blabla;` where after `;` there's eof or membrane_close
                -- this means that there's nothing we can use to create term, but higher parse expects something
                return nil, pos -- so while we're at it, we just tell higher up that no valid term found
            end

            parse_negotiation = function(tokens, pos) -- handle negotiation: term term //left associative. yau can think of it as left accumulates everything on the right ((term term) term)
                local term, pos = parse_term(tokens, pos)
               
                if (term == nil) then return nil, pos end

                local tok = tokens[pos] -- slight optimization
                local node = term
                while
                    tok and (
                    tok.type == TOKENTYPE.MEMBRANE_OPEN or
                    tok.type == TOKENTYPE.NUMBER or
                    tok.type == TOKENTYPE.STRING or
                    tok.type == TOKENTYPE.LABEL) do -- Check if next token is a term (not a delimiter)
                    term, pos = parse_term(tokens, pos) -- previous check guarantees that parse_term won't return (nil, pos)
                    tok = tokens[pos] -- we update tok
                    node = AST.NEGOTIATION(node, term) -- Keep nesting leftwards
                end
                return node, pos
            end

            local check_token = function (tok, tt)
                return (tok ~= nil) and tok.type == tt
            end

            parse_product = function(tokens, pos) -- handle ?product: frame | term
                local term, pos = parse_negotiation(tokens, pos)
               
                if check_token(tokens[pos], TOKENTYPE.FINISH_ELEMENT) then -- it's a frame
                    -- there must be comma, but trailing one is optional.
                    -- meaning (5,) must be valid frame with 1 element,
                    -- while (5) is just the element
                    local items = {term}
                    repeat
                        term, pos = parse_negotiation(tokens, pos + 1)
                        if term then -- for the sake of trailing comma, there might be nil
                            table.insert(items, term)
                        end
                    until not check_token(tokens[pos], TOKENTYPE.FINISH_ELEMENT)
                    return AST.FRAME(items), pos
                else -- it's not a frame
                    return term, pos -- could return (nil, pos) from parse_term and thats fine
                end
            end

            parse_sequence = function(tokens, pos) -- handle ?sequence: (product ";")* [creturn]
                local term, pos = parse_product(tokens, pos)
               
                -- we could have no sequence at all, so first thing we check if there is sequence
                if check_token(tokens[pos], TOKENTYPE.FINISH_ACTION) then -- it's a sequence
                    -- there must be semicolon, but trailing one sets creturn to nil.
                    -- meaning (5;) must be valid sequence with 1 element,
                    -- while (5) is just the element,
                    -- but if it's (5;5), last element conidered as return value on membrane finish
                    local prod = {}
                    local ret = term
                    repeat
                        table.insert(prod, ret)
                        ret = nil
                        term, pos = parse_product(tokens, pos + 1)
                        if term then -- sometimes there might be not vaild term after semicolon
                            ret = term
                        end
                    until not check_token(tokens[pos], TOKENTYPE.FINISH_ACTION)
                    return AST.SEQUENCE(prod, ret or AST.GAP()), pos
                else -- it's not a sequence
                    return term, pos -- could return (nil, pos) from parse_term and thats fine
                end
            end

            local tokenize = function(code)
                local tokens = {}
                local i = 1
                local line = 1
                local choff = 0
                while i <= #code do
                    local c = code:sub(i, i)
                    if c:match("%s") then  -- Skip whitespace
                        if c == "\n" then
                            line = line + 1
                            choff = i
                        end
                        i = i + 1
                    --elseif c == "0" and code:sub(i+1,i+1):lower() == "x" then -- Number Hex (syntax sugar. Removed in favour of Ada/Smalltalk style "can" keys)
                    --    local hex = code:match("^0x%x+", i)
                    --    table.insert(tokens, {type = TOKENTYPE.NUMBER, value = tonumber(hex), at = {char = i - choff, line = line}})
                    --    i = i + #hex
                    --elseif c == "0" and code:sub(i+1,i+1):lower() == "b" then -- Number Binary
                    --    local bin = code:match("^0b[01]+", i)
                    --    local val = tonumber(bin:sub(3), 2)
                    --    table.insert(tokens, {type = TOKENTYPE.NUMBER, value = val, at = {char = i - choff, line = line}})
                    --    i = i + #bin
                    elseif c:match("%d") then -- Number Scientific/Basic
                        local num = code:match("^%d+%.?%d*[eE][+-]?%d+", i) or
                                    code:match("^%d+%.?%d*", i)
                        table.insert(tokens, {type = TOKENTYPE.NUMBER, value = tonumber(num), at = {char = i - choff, line = line}})
                        i = i + #num
                    elseif c == '"' then  -- String
                        local value = {}
                        local i_start = i
                        i = i + 1  -- skip opening quote

                        while i <= #code do
                            local ch = code:sub(i, i)

                            if ch == '\\' then
                                -- Escape sequence
                                i = i + 1
                                if i > #code then
                                  error("Unfinished escape sequence at end of string", 2)
                                end
                                local next = code:sub(i, i)

                                if next == 'n' then
                                    table.insert(value, '\n')  -- Newline
                                elseif next == 't' then
                                    table.insert(value, '\t')  -- Tab
                                elseif next == 'r' then
                                    table.insert(value, '\r')  -- Carriage return
                                elseif next == '"' then
                                    table.insert(value, '"')   -- Escaped quote
                                elseif next == '\\' then
                                    table.insert(value, '\\')  -- Escaped backslash
                                else
                                    -- Unknown escape: treat literally (or error)
                                    table.insert(value, '\\')
                                    table.insert(value, next)
                                end
                                i = i + 1
                           
                            elseif ch == '\n' then
                                -- Direct Newlines are whitespace even here
                                line = line + 1
                                choff = i  -- Reset char offset after newline
                                i = i + 1
                            elseif ch == '"' then
                                -- Closing quote
                                i = i + 1
                                break
                            else
                                -- Regular character
                                table.insert(value, ch)
                                i = i + 1
                            end
                        end

                        table.insert(tokens, {
                            type = TOKENTYPE.STRING,
                            value = table.concat(value),
                            at = {char = i_start - choff, line = line}
                        })
                    elseif c:match("[a-zA-Z_]") then  -- CNAME label
                        local label = code:match("^[_a-zA-Z][_a-zA-Z0-9]*", i)
                        table.insert(tokens, {type = TOKENTYPE.LABEL, value = label, at = {char = i - choff, line = line}})
                        i = i + #label
                    elseif c:match("^[+%-*/%%=<>!&|^~:@#%.`$]+$") then  -- SNAME label symbol
                        local sym = code:match("^[+%-*/%%=<>!&|^~:@#%.`$]+", i)
                        table.insert(tokens, {type = TOKENTYPE.LABEL, value = sym, at = {char = i - choff, line = line}})
                        i = i + #sym
                    elseif c == "(" or c == "{" or c == "[" then  -- Open brackets
                        table.insert(tokens, {
                            type = TOKENTYPE.MEMBRANE_OPEN,
                            value = ({["["]=1,["{"]=2,["("]=3})[c],
                            at = {char = i - choff, line = line}})
                        i = i + 1
                    elseif c == ")" or c == "}" or c == "]" then  -- Close brackets
                        table.insert(tokens, {
                            type = TOKENTYPE.MEMBRANE_CLOSE,
                            value = ({["]"]=1,["}"]=2,[")"]=3})[c],
                            at = {char = i - choff, line = line}})
                        i = i + 1
                    elseif c == "," then
                        table.insert(tokens, {type = TOKENTYPE.FINISH_ELEMENT, at = {char = i - choff, line = line}})
                        i = i + 1
                    elseif c == ";" then
                        table.insert(tokens, {type = TOKENTYPE.FINISH_ACTION, at = {char = i - choff, line = line}})
                        i = i + 1
                    else
                        error("Unexpected character: '" .. c .. "' at line:"..tostring(line)..", char:"..tostring(i - choff), 2)
                    end
                end
                return tokens
            end
            return function (src)
                local tokens = tokenize(src)
                local ast, pos = parse_sequence(tokens, 1) -- this is purely just to keep pos local to parsing state
                if pos <= #tokens then
                    error("Parse error: extra tokens after sequence: "..tostring(pos).." "..tostring(#tokens), 2)
                end
                return ast
            end
        end)() -- returns src's AST prepared for loading into NegI state via FLESH.load (and yes, it's a function constructor)

        -- manifests responsible for (manifests <> negI_representation)
        FLESH.NegI.RootContext.parse_negi = FLESH.make.Manifest(FLESH.NegI.RootContext.Parser.state, {
            nodes = {}, -- TODO: pull out AST from FLESH.NegI.parse into a Frame
            parse = FLESH.NegI.parse
        })

        FLESH.NegI.depict = (function ()
           
        end)()

        FLESH.NegI.RootContext.depict_negi = FLESH.make.Manifest(FLESH.NegI.RootContext.Depictor.state, {
            depictions = {},
            --identifier = nil, -- helps with finding
            depict = FLESH.NegI.depict,
        })

        FLESH.make.unthunk()
        
        FLESH.Host = {}

        FLESH.Host.Types = { -- while it's a mapping table, OPHANIM fundamentally disagree with lua on type existance, so for example userdata can't be capchecked
            ["nil"] = FLESH.NegI.RootContext.gap,
            boolean = FLESH.make.Manifest({
                    can = {
                        ["in"] = {call = capability_check},
                        ["="] = make_host_res_init("boolean")
                },{
                    can = {
                        ["|"] = {call = make_trans_op("or")},
                        ["&"] = {call = make_trans_op("and")},
                        ["~"] = {get = make_trans("not")},
                        ["=="] = {call = make_trans_op("==")},
                        ["~="] = {call = make_trans_op("~=")},
                        to = {
                            can = {
                                NegIManifest = {get = FLESH.make.ArtifactCore("return FLESH.make.Number(self.state) ")},
                    }}}
                }}),
            number = FLESH.make.Manifest({
                    can = {
                        ["in"] = {call = capability_check},
                        ["="] = make_host_res_init("number")
                },{
                    can = {
                        ["+"] = {call = make_trans_op("+")},
                        ["-"] = {call = make_trans_op("-")},
                        ["*"] = {call = make_trans_op("*")},
                        ["/"] = {call = make_trans_op("/")},
                        ["%"] = {call = make_trans_op("%")},
                        ["^"] = {call = make_trans_op("^")},
                        ["|"] = {call = make_trans_op("|")},
                        ["&"] = {call = make_trans_op("&")},
                        ["<<"] = {call = make_trans_op("<<")},
                        [">>"] = {call = make_trans_op(">>")},
                        ["=="] = {call = make_trans_op("==")},
                        ["~="] = {call = make_trans_op("~=")},
                        ["<"] = {call = make_trans_op("<")},
                        [">"] = {call = make_trans_op(">")},
                        ["<="] = {call = make_trans_op("<=")},
                        [">="] = {call = make_trans_op(">=")},
                        abs = {get = make_trans("math.abs")},
                        acos = {get = make_trans("math.acos")},
                        asin = {get = make_trans("math.asin")},
                        atan = {get = make_trans("math.atan")},
                        ceil = {get = make_trans("math.ceil")},
                        cos = {get = make_trans("math.cos")},
                        deg = {get = make_trans("math.deg")},
                        exp = {get = make_trans("math.exp")},
                        floor = {get = make_trans("math.floor")},
                        fmod = {get = make_trans("math.fmod")},
                        frexp = {get = make_trans("math.frexp")},
                        huge = {get = make_trans("math.huge")},  -- const
                        ldexp = {get = nil}, -- math.ldexp (m, e) - Returns m2e, where e is an integer.
                        log = {get = make_trans("math.log")},
                        max = {get = make_trans("math.max")},
                        maxinteger = {get = make_trans("math.maxinteger")}, -- const
                        min = {get = make_trans("math.min")},
                        mininteger = {get = make_trans("math.mininteger")}, -- const
                        modf = {get = nil}, -- Returns the integral part of x and the fractional part of x. Its second result is always a float.
                        pi = {get = make_trans("math.pi")}, -- const
                        rad = {get = make_trans("math.rad")},
                        --random = {get = make_trans("math.random")},
                        --randomseed = {call = nil}, -- [x, [y]]
                        sin = {get = make_trans("math.sin")},
                        sqrt = {get = make_trans("math.sqrt")},
                        tan = {get = make_trans("math.tan")},
                        tointeger = {get = make_trans("math.tointeger")},
                        type = {get = nil}, -- returns "integer" or "float" or fail
                        ult = {call = nil}, -- math.ult (m, n)
                        to = {
                            can = {
                                NegIManifest = {get = FLESH.make.ArtifactCore("return FLESH.make.Number(self.state) ")},
                                string = {get = FLESH.make.ArtifactCore([[
                                    return { -- UNFINISHED
                                        protocol = FLESH.KES:resolve(host_types.state.items[host_types.state.labels.string]).state,
                                        state = tostring(self.state)}
                                ]])
                    }}}}
                }}),
            string = FLESH.make.Manifest({
                    can = {
                        ["in"] = {call = capability_check},
                        ["="] = make_host_res_init("string")
                },{
                    can = {
                        ["+"] = {call = make_trans_op("..")},
                        ["=="] = {call = make_trans_op("==")},
                        ["~="] = {call = make_trans_op("~=")},
                        format = {call = FLESH.make.ArtifactCore([[
                            -- check if arg is frame and go on
                        ]])},
                        size = {get = make_trans("string.len")},
                        lower = {get = make_trans("string.lower")},
                        upper = {get = make_trans("string.upper")},
                        reverse = {get = make_trans("string.reverse")},
                        to = {
                            can = {
                                NegIManifest = {get = FLESH.make.ArtifactCore("return FLESH.make.String(self.state) ")},
                                number = {get = FLESH.make.ArtifactCore([[
                                    return {
                                        protocol = FLESH.KES:resolve(host_types.state.items[host_types.state.labels.number]).state,
                                        state = tonumber(self.state)}
                                ]])}}}
                    }
                }}),
            userdata = nil, -- the lua lables it userdata, but basically it's a capability wildcard that OPHANIM can't use to check against userdata instance
            ["function"] = FLESH.make.Manifest({
                    can = {
                    ["in"] = {call = capability_check},
                    ["="] = make_host_res_init("function")
                },{
                    can = {
                        dump = {get = make_trans("string.dump")}
                    },
                    call = FLESH.make.ArtifactCore([[
                        local frame_p
                        return FLESH:import(self.state(table.unpack(args)))
                    ]])
                }}),
            thread = FLESH.make.Manifest({ --
                    can = {
                        ["in"] = {call = capability_check},
                        ["="] = make_host_res_init("thread")
                },{
                    can = {
                        close = {get = FLESH.make.ArtifactCore([[ ]])},
                        isyieldable = {get = FLESH.make.ArtifactCore([[ ]])},
                        resume = {get = FLESH.make.ArtifactCore([[ ]])},
                        status = {get = FLESH.make.ArtifactCore([[ ]])},
                        wrap = {get = FLESH.make.ArtifactCore([[ ]])},
                    }
                }}),
            table = FLESH.make.Manifest({ -- this also somewhat capability wildcard, but the importer uses different protocol for table, if it's table isn't empty
                    can = {
                        ["in"] = {call = capability_check},
                        ["="] = make_host_res_init("table")
                },{
                    can = {
                        ["+"] = {call = make_trans_op("..")},
                        ["=="] = {call = make_trans_op("==")},
                        ["~="] = {call = make_trans_op("~=")},
                        size = {call = make_trans("#")},
                        to = {
                            can = {
                                NegIManifest = {get = FLESH.make.ArtifactCore("return FLESH.make.Number(self.state) ")},
                        }}
                    },
                    call = FLESH.make.ArtifactCore([[
                        -- TODO: we somehow need to check if arg is a number or a manifest
                        return FLESH:import(self[arg.state]) -- we need to chanage the intent of import, so it would use this data
                    ]])
                }}),
            unknown = FLESH.make.Manifest({
                    can = {
                        ["in"] = {call = capability_check},
                        ["="] = FLESH.make.ArtifactCore([[ -- UNFINISHED
                            return {protocol = self.state,state = arg}
                        ]])
                },{}}),
        }

       

        FLESH.import = (function ()
            local value_mapping = function (self, o)
                return {
                    protocol = FLESH.Host.Types[type(o)].state, -- TODO: I need to rework the structure
                    state = o} end

            local gen_mt_protocol = function (self, mt)
                for k,v in pairs(mt) do
                   
                end
            end

            local mapping = {
                ["nil"] = (function ()
                    local instance = nil -- I should think on how I can integrate it
                    return function (self, o)
                        return instance
                end end)(),
                boolean = (function ()
                    local instances = {value_mapping(self, false), value_mapping(self, true)} -- we keep lua from creating new tables for finite amount of states, by just caching them
                    return function (self, o)
                        return instances[o and 2 or 1]
                end end)(),
                number = value_mapping,
                string = value_mapping,
                userdata = function (self, o)
                    local capability = getmetatable(o)
                    -- we generate capability mapping no matter the reason
                    return {protocol = gen_mt_protocol(self, o), state = o}
                end,
                ["function"] = value_mapping,
                thread = value_mapping,
                table = function (self, o)
                    local mt = getmetatable(o)
                    if mt then
                        return {protocol = gen_mt_protocol(self, mt), state = o} -- unfinished, since it doesn't handle default table behaivour
                    else
                        return value_mapping(self, o)
                    end
                end
            }

            return function (self, o) -- imports lua object "o" inside OPHANIM environment
                -- it should find OPHANIM's host knowledge and apply appropriate interface from it.
                local pif = mapping[type(o)]
                if pif then
                    return pif(self, o)
                else
                    -- at this point I should make Error constructors, preferrably that would have error codes
                end
            end end)()

        FLESH.Host.Frame = {
            meta = FLESH.make.Frame({
                name = FLESH:import("Lua 5.5"),
                version = FLESH:import("0.0.1")
            }),
            intrinsics = FLESH.make.Frame({
                types = FLESH.make.Frame(FLESH.Host.Types),
                concepts = nil,
            }),
            authority = FLESH.make.Frame({
                coroutine = nil,
                debug = nil,
                io = nil,
                os = nil,
                package = nil,
            }),  
        }

        --[[ -- since OPHANIM structured differently, lua interafec should be altered to fit the philosophy
        basic -- ???
        _G -- Host
        _VERSION -- Host
        assert -- Host
        collectgarbage -- Host
        dofile -- Host
        error -- Host
        getmetatable -- table, userdata
        ipairs -- table, userdata
        load -- Host
        loadfile -- Host
        next -- table, userdata
        pairs -- table, userdata
        pcall -- Host
        print -- Host (we don't have any other way to interact with lua console other than io)
        rawequal -- lua types
        rawget -- table
        rawlen -- table, string
        rawset -- table
        require -- Host
        select -- function?
        setmetatable -- table, userdata
        tonumber -- string, number
        tostring -- lua types
        type -- lua types
        warn -- Host
        xpcall -- Host
        ]]

        local rcf = FLESH.make.Frame(FLESH.NegI.RootContext)
        FLESH.KES:write_entry("NegI", rcf) -- NegI core interface
        FLESH:do_action(rcf.protocol.can.load.get, rcf)
        FLESH.KES:stage_commit(function (q,m) return FLESH.KES:write_entry(q,m) end);

        local manifest = { -- manifest structure reference ()
            template = {
                protocol = { -- always table
                    can = {}, -- prio, find appropriate Label in front of manifest (maybe I should make this into frame, that depicts the environment for the label in front of it)
                    ask = nil, -- default case for "can", can work with call but it's heavily advised to not use with call, otherwise it will cause confusion)
                    call = nil, -- not found appropriate Label in can, do it if there is negotiation
                    get = nil, -- not found appropriate Label in can, do it anyways with (if no call) or without negotioation. this rule exist to describle RAII
                    wrap = nil, -- wrapping up the site
                    -- ownership stuff
                    res = nil, -- resource enumeration via callback
                    fork = nil, -- triggered upon invocation inside foreign layer, used to create forks of mutable Manifests. Expected to return new Manifest
                    lift = nil, -- triggered upon transfering Manifest into a layer that expects it
                },
                state = { -- internal state of manifest, could only be used by protocol it's bundled with.
           
        }}}

        FLESH:reset()
        return FLESH
    end
           
    return {
    _VERSION="0.0.1",
    newstate = newstate,
} end)()