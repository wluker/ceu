_GATES = {
    n_ands = nil,
    n_gtes = nil,
    trgs   = nil,
}

local VARS = nil

function alloc ()
    local g = _GATES.n_gtes
    _GATES.n_gtes = _GATES.n_gtes + 1
    return g
end

F = {
    Root_pre = function (me)
        _GATES.n_ands = 0
        _GATES.n_gtes = 0
        _GATES.trgs = { 0 }     -- 0=all undefined should point to [0]
        VARS = {}
    end,
    Root = function (me)
        local TRG0 = 1
        for var in pairs(VARS) do
            var.trg0 = TRG0
            TRG0 = TRG0 + 1 + #var.trgs
            _GATES.trgs[#_GATES.trgs+1] = #var.trgs
            for _,gte in ipairs(var.trgs) do
                _GATES.trgs[#_GATES.trgs+1] = gte
            end
        end
    end,

    ParAnd_pre = function (me)
        if me.forever == 'yes' then
            return
        end
        me.gte0 = _GATES.n_ands
        _GATES.n_ands = _GATES.n_ands+#me
    end,

    -- gates for cleaning
    ParOr_pre = function (me)
        me.gtes = { [1]=_GATES.n_gtes, [2]=nil }
    end,
    ParOr = function (me)
        me.gtes[2] = _GATES.n_gtes
    end,
    Loop_pre     = function(me) F.ParOr_pre(me) end,
    Loop         = function(me) F.ParOr(me)     end,
    SetBlock_pre = function(me) F.ParOr_pre(me) end,
    SetBlock     = function(me) F.ParOr(me)     end,

    Async = function (me)
        me.gte = alloc()
    end,

    EmitE = function (me)
        local acc,_ = unpack(me)
        -- internal event
        if acc.var.int then
            me.gte_trg = alloc()
            me.gte_cnt = alloc()
        end
    end,

    AwaitT = function (me)
        me.gte = alloc()
    end,
    AwaitE = function (me)
        local acc,_ = unpack(me)
        me.gte = alloc()
        VARS[acc.var] = true
        local t = acc.var.trgs
        t[#t+1] = me.gte
    end,
}

_VISIT(F)
