-- TODO: rename to flow
_ANA = {
    ana = {
        isForever  = nil,
        reachs   = 0,      -- unexpected reaches
        unreachs = 0,      -- unexpected unreaches
    }
}

-- avoids counting twice (due to loops)
-- TODO: remove
local __inc = {}
function INC (me, c)
    if __inc[me] then
        return true
    else
        _ANA.ana[c] = _ANA.ana[c] + 1
        __inc[me] = true
        return false
    end
end

-- [false]  => never terminates
-- [true]   => terminates w/o event

function OR (me, sub, short)

    -- TODO: short
    -- short: for ParOr/Loop/SetBlock if any sub.pos is equal to me.pre,
    -- then we have a "short circuit"

    for k in pairs(sub.ana.pos) do
        if k ~= false then
            me.ana.pos[false] = nil      -- remove NEVER
            me.ana.pos[k] = true
        end
    end
end

function COPY (n)
    local ret = {}
    for k in pairs(n) do
        ret[k] = true
    end
    return ret
end

function _ANA.CMP (n1, n2)
    for k1 in pairs(n1) do
        if not n2[k1] then
            return false
        end
    end
    for k2 in pairs(n2) do
        if not n1[k2] then
            return false
        end
    end
    return true
end

local LST = {
    Stmts=true, Block=true, Root=true, Dcl_cls=true,
}

F = {
    Root_pos = function (me)
        _ANA.ana.isForever = not (not me.ana.pos[false])
    end,

    Node_pre = function (me)
        if me.ana then
            return
        end

        local top = _AST.iter()()
        me.ana = {
            pre  = (top and top.ana.pre) or { [true]=true },
        }
    end,
    Node = function (me)
        if me.ana.pos then
            return
        end
        if LST[me.tag] and me[#me] then
            me.ana.pos = COPY(me[#me].ana.pos)  -- copy lst child pos
        else
            me.ana.pos = COPY(me.ana.pre)       -- or copy own pre
        end
    end,

    Dcl_cls_pre = function (me)
        if me ~= _MAIN then
            me.ana.pre = { [me.id]=true }
        end
    end,
    Org = function (me)
        me.ana.pos = { [false]=true }       -- an instance runs forever
    end,

    Stmts_bef = function (me, sub, i)
        if i == 1 then
            -- first sub copies parent
            sub.ana = {
                pre = COPY(me.ana.pre)
            }
        else
            -- broken sequences
            if me[i-1].ana.pos[false] and (not me[i-1].ana.pre[false]) then
                --_ANA.ana.unreachs = _ANA.ana.unreachs + 1
                me.__unreach = true
                WRN( INC(me, 'unreachs'),
                     sub, 'statement is not reachable')
            end
            -- other subs follow previous
            sub.ana = {
                pre = COPY(me[i-1].ana.pos)
            }
        end
    end,

    ParOr_pos = function (me)
        me.ana.pos = { [false]=true }
        for _, sub in ipairs(me) do
            OR(me, sub, true)
        end
        if me.ana.pos[false] then
            --_ANA.ana.unreachs = _ANA.ana.unreachs + 1
            WRN( INC(me, 'unreachs'),
                 me, 'at least one trail should terminate')
        end
    end,

    ParAnd_pos = function (me)
        -- if any of the sides run forever, then me does too
        -- otherwise, behave like ParOr
        for _, sub in ipairs(me) do
            if sub.ana.pos[false] then
                me.ana.pos = { [false]=true }
                --_ANA.ana.unreachs = _ANA.ana.unreachs + 1
                WRN( INC(me, 'unreachs'),
                     sub, 'trail should terminate')
                return
            end
        end

        -- like ParOr, but remove [true]
        local onlyTrue = true
        me.ana.pos = { [false]=true }
        for _, sub in ipairs(me) do
            OR(me, sub)
            if not sub.ana.pos[true] then
                onlyTrue = false
            end
        end
        if not onlyTrue then
            me.ana.pos[true] = nil
        end
    end,

    ParEver_pos = function (me)
        me.ana.pos = { [false]=true }
        local ok = false
        for _, sub in ipairs(me) do
            if sub.ana.pos[false] then
                ok = true
                break
            end
        end
        if not ok then
            --_ANA.ana.reachs = _ANA.ana.reachs + 1
            WRN( INC(me, 'reachs'),
                 me, 'all trails terminate')
        end
    end,

    If = function (me)
        if me.isFor then
            me.ana.pos = COPY(me.ana.pre)
            return
        end

        me.ana.pos = { [false]=true }
        for _, sub in ipairs{me[2],me[3]} do
            OR(me, sub)
        end
    end,

    SetBlock_pre = function (me)
        me.ana.pos = { [false]=true }   -- `return/break´ may change this
    end,
    Return = function (me)
        local top = _AST.iter((me.tag=='Return' and 'SetBlock') or 'Loop')()
        me.ana.pos = COPY(me.ana.pre)
        OR(top, me, true)
        me.ana.pos = { [false]=true }

--[[
    -- short: for ParOr/Loop/SetBlock if any sub.pos is equal to me.pre,
    -- then we have a "short circuit"
DBG(me.ana.pre, top.ana.pre)
        if me.ana.pre == top.ana.pre then
            for par in _AST.iter(_AST.pred_par) do
                if par.depth < top.depth then
                    break
                end
                for _, sub in ipairs(par) do
DBG(sub.tag)
                    if (not sub.ana.pos[false]) then
                        _ANA.ana.unreachs = _ANA.ana.unreachs + 1
                        sub.ana.pos = { [false]=true }
                    end
                end
            end
        end
]]
    end,
    SetBlock = function (me)
        local blk = me[2]
        if   (not blk.ana.pos[false])
        and  (me[2].tag ~= 'Async')     -- async is assumed to terminate
        then
            --_ANA.ana.reachs = _ANA.ana.reachs + 1
            WRN( INC(me, 'reachs'),
                 blk, 'missing `return´ statement for the block')
        end
    end,

    Loop_pre = 'SetBlock_pre',
    Break    = 'Return',

    Loop = function (me)
-- TODO: why?
        if me.isFor then
            me.ana.pos = COPY(me[1].ana.pos)
            return
        end

        if me[1].ana.pos[false] then
            --_ANA.ana.unreachs = _ANA.ana.unreachs + 1
            WRN( INC(me, 'unreachs'),
                 me, '`loop´ iteration is not reachable')
        end

--[[
        -- pre = pre U pos
        if not me[1].ana.pos[false] then
            _AST.union(me[1], next(me.ana.pre), me[1].ana.pos)
        end
]]
    end,

    Async = function (me)
        if me.ana.pre[false] then
            me.ana.pos = COPY(me.ana.pre)
        else
            me.ana.pos = { ['ASYNC_'..me.n]=true }
        end
    end,

    SetAwait = function (me)
        local set, awt = unpack(me)
        set.ana.pre = COPY(awt.ana.pos)
        set.ana.pos = COPY(awt.ana.pos)
        me.ana.pre = COPY(awt.ana.pre)
        me.ana.pos = COPY(set.ana.pos)
    end,

    AwaitExt = function (me)
        local e = unpack(me)
        if me.ana.pre[false] then
            me.ana.pos = COPY(me.ana.pre)
        else
            -- use a table to differentiate each instance
            me.ana.pos = { [{e.evt and e.evt or 'WCLOCK'}]=true }
        end
    end,
    AwaitInt = 'AwaitExt',
    AwaitT   = 'AwaitExt',

    AwaitN = function (me)
        me.ana.pos = { [false]=true }
    end,

    Var = function (me)
        local var = me.var
-- TODO
do return end
        if var.isTmp == true then
            var.isTmp = COPY(me.ana.pre)
        else
            var.isTmp = _ANA.CMP(var.isTmp, me.ana.pre)
        end
    end,
}

local _union = function (a, b, keep)
    if not keep then
        local old = a
        a = {}
        for k in pairs(old) do
            a[k] = true
        end
    end
    for k in pairs(b) do
        a[k] = true
    end
    return a
end

-- if nested node is reachable from "pre", join with loop POS
function _ANA.union (root, pre, POS)
    local t = {
        Node = function (me)
            if me.ana.pre[pre] then         -- if matches loop begin
DBG('SIM', me.ln, pre)
                _union(me.ana.pre, POS, true)
            end
        end,
    }
    _AST.visit(t, root)
end

_AST.visit(F)
