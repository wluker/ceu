local yields = {
    EOF           = 'end of file',
    Par           = 'par',
    Par_And       = 'par/and',
    Par_Or        = 'par/or',
    Escape        = 'escape',
    Loop          = 'loop',
    Async         = 'async',
    Async_Thread  = 'async/thread',
    Async_Isr     = 'async/isr',
    Code          = 'code',
    Ext_Code      = 'external code',
    Data          = 'data',
    Nat_Block     = 'native block',
    Await_Ext     = 'await',
    Await_Evt     = 'await',
    Await_Wclock  = 'await',
    Await_Forever = 'await',
    Emit_ext_req  = 'request',
    Emit_Evt      = 'emit',
    Abs_Await     = 'await',
    Abs_Spawn     = 'spawn',
    Kill          = 'kill',
}

local function run (par, i, Var)
    local me = par[i]
    if me == nil then
        return run(par.__par, par.__i+1, Var)
    elseif not AST.isNode(me) then
        return run(par, i+1, Var)
    end
--DBG('---', me.tag)
--AST.dump(me)

    -- error: yielding statement
    if yields[me.tag] then
        ASR(false, Var,
            'uninitialized variable "'..Var.id..'" : '..
            'reached `'..yields[me.tag]..'´ '..
            '('..me.ln[1]..':'..me.ln[2]..')')

    -- error: access to Var
    elseif me.tag == 'ID_int' then
        if me.dcl == Var then
            ASR(false, Var,
                'uninitialized variable "'..Var.id..'" : '..
                'reached read access '..
                '('..me.ln[1]..':'..me.ln[2]..')')
        end

    elseif me.tag == 'If' then
        local _, t, f = unpack(me)
        run(t, 1, Var)
        run(f, 1, Var)

    -- ok: found assignment
    elseif me.tag=='Set_Any' or me.tag=='Set_Exp' then
        local _, to = unpack(me)
        local ID_int = AST.asr(to,'Exp_Name', 1,'ID_int')
        if ID_int.dcl == Var then
            return true, nil            -- stop, found init
        end
    elseif me.tag=='Set_Await_many' then
        local _, Varlist = unpack(me)
        for _, ID_int in ipairs(Varlist) do
            if ID_int.dcl == Var then
                return true, nil        -- stop, found init
            end
        end
    end
    return run(me, 1, Var)
end

F = {
    __i = nil,
    Stmts__BEF = function (me, sub, i)
        F.__i = i
    end,

    Var = function (me)
        local tp = unpack(me)
        if me.is_implicit or TYPES.check(tp,'?') then
            -- ok: don't need initialization
            return
        else
            run(me, #me+1, me)
        end
    end,
}

AST.visit(F)
