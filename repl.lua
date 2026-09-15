local pprint = require("pprint")
local ophanim = require("ophanim")
--local ldbg = require("lua_utils/debugger")

local OState = ophanim.newstate()
--pprint(OState)
OState.pprint = pprint

local contain_test = function ()
    io.write("testing isolation (1):\t")
    return OState:dispatch(OState.NegI.parse([[ [a:1; b:{;a}; (a:55;b())[] ][] ]])).state
end
local quote_test = function ()
    io.write("testing quoting (55):\t")
    return OState:dispatch(OState.NegI.parse([[ [a:1; b:{;a}; [a:55;b()][] ][] ]])).state
end
local grounding_test = function ()
    io.write("testing grounding (1):\t")
    return OState:dispatch(OState.NegI.parse([[ [a:1; b:[;a]; [a:55;b()][] ][] ]])).state
end
local labeling_test = function ()
    io.write("testing labeling (3):\t")
    return OState:dispatch(OState.NegI.parse([[ [a : 2; a : 3; a][] ]])).state
end
local swap_test = function ()
    io.write("testing swap (3):\t") -- need to change how tests are performed
    return OState:dispatch(OState.NegI.parse([[ [
        a : 2;
        b : 3;
        a : b, b : a;
        a][] ]])).state
end
local passing_test = function ()
    io.write("testing passing (9):\t")
    return OState:dispatch(OState.NegI.parse([[ [
        NegI load;
        f : [
            b : 303;
            a : 9;
            pass [;r] (r:a,);
            a : 88;
        a];
        f[]
    ][] ]])).state
end
local factorial_test = function ()
    io.write("testing factorial (120):\t")
    return OState:dispatch(OState.NegI.parse([[ [
        NegI load;
        f : [
            ans : 1;
            i : 2;
            loop : [
                ans : ans * i;
                i : i + 1;
                ( pass [;ans], pass loop, pass loop,)[i <> n + 2](ans : ans, i : i, n : n)
            ];
            loop (n : 5,)
        ];
        f[]
    ][] ]])).state
end

print("LOADING=========================================================")
pprint(contain_test())
pprint(quote_test())
pprint(grounding_test())
pprint(labeling_test())
pprint(swap_test())
pprint(passing_test())
pprint(factorial_test())
print("NegI REPL v0.0.4 (Pre-Alpha)====================================")
--print("-- for help write `REPL help`")
--print("-- for tutorial write `REPL tutorial`")

local running = true
local rmf = OState.make.Manifest({ -- we describle REPL authority here, instead of using arbitrary commands
        can = {
            exit = {get = OState.make.ArtifactCore([[self.state.stop_repl()]], "REPL can exit call")},
            reset = {get = OState.make.ArtifactCore([[
                while self.state.repl_layer < FLESH.KES:get_context() do FLESH.KES:pop_layer() end
                FLESH.KES:push_layer(FLESH.KES:get_context(),true)
            ]], "REPL can reset get")},
--            tutorial = {get = OState.NegI.parse([[ -- Petition is not finished, so it won't work, but that's how Manifest should look like if contructed from NegI side
--                Petition = env "console" (
--                
--                );
--                cli write "
--You sent drone inside some unknown possibly anomalous place.\n
--The drone is your hands and eyes inside this place.\n
--In your authority a terminal is available for the purpose of controlling and programming that drone on the fly.\n\n
--
--(press `enter` to continue)\n
--";
--                cli write "
--First things first before doing anything, let's learn how to look around the environment.\n\n
--
--(write `context inner`)
--";
--                cli write "
--As you can see you do not have an authority to do so.\n
--Let's load relevant instruments and try again.\n\n
--
--(write `NegI load`)
--";
--                cli write "
--Now let's lern how to use workspace\n.
--
--(write `NegI load`)
--";
--
--            ]])}
        }
    },{
        repl_layer = OState.KES:get_context(),
        stop_repl = function () running = false end,
    })
local rsl = OState.KES:write_entry("REPL", rmf)


OState.KES:push_layer(OState.KES:get_context(),true)
while running do
    io.write(">")
    local input = io.read()
    local e = OState.NegI.parse(input) or OState.NegI.RootContext.gap
    e = OState:dispatch(e); e = e or OState.NegI.RootContext.gap -- evaluation
    e = OState:dispatch(e); e = (e ~= OState.NegI.RootContext.gap) and e or nil -- get
    OState.KES:stage_fill_reserve(e)
    OState.KES:stage_commit()
    pprint.pformat((e or {}).state, {depth_limit = 6}, io.write)
    io.write("\n")
end
OState.KES:pop_layer()
-- starting to make the system alive