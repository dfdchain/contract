type State = 'NOT_INITED' | 'COMMON' | 'PAUSED' | 'STOPPED'

type Storage = {
    name: string,
    symbol: string,
    supply: int,
    precision: int,
    users: Map<int>, 
    allowed: Map<string>,
    lockedAmounts: Map<string>,
    state: string,
    allowLock: bool,
    admin: string
}

var M = Contract<Storage>()

function M:init()
    self.storage.name = ''
    self.storage.symbol = ''
    self.storage.supply = 0
    self.storage.precision = 0
    self.storage.users = {}
    self.storage.lockedAmounts = {}
    self.storage.state = 'NOT_INITED'
    self.storage.admin = caller_address
    self.storage.allowLock = false
    self.storage.allowed = {}
end

let function checkAdmin(self: table)
    if self.storage.admin ~= caller_address then
        return error("you are not admin, can't call this function")
    end
end

-- parse a,b,c format string to [a,b,c]
let function parse_args(arg: string, count: int, error_msg: string)
    if not arg then
        return error(error_msg)
    end
    let parsed = string.split(arg, ',')
    if (not parsed) or (#parsed ~= count) then
        return error(error_msg)
    end
    return parsed
end

let function parse_at_least_args(arg: string, count: int, error_msg: string)
    if not arg then
        return error(error_msg)
    end
    let parsed = string.split(arg, ',')
    if (not parsed) or (#parsed < count) then
        return error(error_msg)
    end
    return parsed
end

let function arrayContains(col: Array<object>, item: object)
    if not item then
        return false
    end
    var value: object
    for _, value in ipairs(col) do
        if value == item then
            return true
        end
    end
    return false
end

function M:on_deposit(amount: int)
    return error("not support deposit to token")
end

-- arg: name,symbol,supply,precision
function M:init_token(arg: string)
    checkAdmin(self)
    pprint('arg:', arg)
    if self.storage.state ~= 'NOT_INITED' then
        return error("this token contract inited before")
    end
    let parsed = parse_args(arg, 4, "argument format error, need format: name,symbol,supply,precision")
    let info = {name: parsed[1], symbol: parsed[2], supply: tointeger(parsed[3]), precision: tointeger(parsed[4])}
    if not info.name then
        return error("name needed")
    end
    self.storage.name = tostring(info.name)
    if not info.symbol then
        return error("symbol needed")
    end
    self.storage.symbol = tostring(info.symbol)
    if not info.supply then
        return error("supply needed")
    end
    let supply = tointeger(info.supply)
    if (not supply) or (supply <= 0) then
        return  error("supply must be positive integer")
    end
    self.storage.supply = supply

    self.storage.users[caller_address] = supply

    if not info.precision then
        return error("precision needed")
    end
    let precision = tointeger(info.precision)
    if (not precision) or (precision <= 0) then
        return  error("precision must be positive integer")
    end
    let allowedPrecisions = [1,10,100,1000,10000,100000,1000000,10000000,100000000]
    if not (arrayContains(allowedPrecisions, precision)) then
        return error("precision can only be positive integer in " .. json.dumps(allowedPrecisions))
    end
    self.storage.precision = precision
    self.storage.state = 'COMMON'
    let supplyStr = tostring(supply)
    emit Inited(supplyStr)
end

let function checkState(self: table)
    if self.storage.state == 'NOT_INITED' then
        return error("contract token not inited")
    end
    if self.storage.state == 'PAUSED' then
        return error("contract paused")
    end
    if self.storage.state == 'STOPPED' then
        return error("contract stopped")
    end
end

let function checkStateInited(self: table)
    if self.storage.state == 'NOT_INITED' then
        return error("contract token not inited")
    end
end

let function checkAddress(addr: string)
    let result = is_valid_address(addr)
    if not result then
        return error("address format error")
    end
    return result
end

offline function M:state(arg: string)
    return self.storage.state
end

offline function M:tokenName(arg: string)
    checkStateInited(self)
    return self.storage.name
end

offline function M:precision(_: string)
    checkStateInited(self)
    return self.storage.precision
end

offline function M:tokenSymbol(arg: string)
    checkStateInited(self)
    return self.storage.symbol
end

offline function M:admin(_: string)
    checkStateInited(self)
    return self.storage.admin
end

offline function M:totalSupply(arg: string)
    checkStateInited(self)
    return self.storage.supply
end

offline function M:isAllowLock(_: string)
    let resultStr = tostring(self.storage.allowLock)
    return resultStr
end

function M:openAllowLock(_: string)
    checkAdmin(self)
    checkState(self)
    if self.storage.allowLock then
        return error("this contract had been opened allowLock before")
    end
    self.storage.allowLock = true
    emit AllowedLock("")
end

let function getBalanceOfUser(self: table, addr: string)
    return tointeger(self.storage.users[addr] or 0)
end

offline function M:balanceOf(owner: string)
    checkStateInited(self)
    if (not owner) or (#owner < 1) then
        return error('arg error, need owner address as argument')
    end
    checkAddress(owner)
    let amount = getBalanceOfUser(self, owner)
    pprint('amount: ', amount)
    let amountStr = tostring(amount)
    return amountStr
end

-- arg: limit(1-based),offset(0-based)}
offline function M:users(arg: string)
    pprint('arg=', arg)
    let parsed = parse_args(arg, 2, "argument format error, need format is limit(1-based),offset(0-based)}")
    let info = {limit: tointeger(parsed[1]), offset: parsed[2]}
    let limit = tointeger(info.limit)
    let offset = tointeger(info.offset)
    if (not limit) or (limit < 1) or (not offset) or (offset <0) or ((offset + limit) <= 0) then
        return error("offset is non-negative integer, limit is positive integer")
    end
    let userAddresses: Array<string> = []
    var userAddr: string
    for userAddr in pairs(self.storage.users) do 
        table.append(userAddresses, userAddr)
    end
    var result: Array<string> = []
    if (#userAddresses <= offset) then
        result = []
    else
        var i: int = 0
        for i=offset,(offset+limit-1),1 do
            if i<#userAddresses then
                table.append(result, userAddresses[i+1])
            end
        end
    end
    let resultStr = tojsonstring(result)
    return resultStr
end

-- arg: to_address,integer_amount[,memo]
function M:transfer(arg: string)
    checkState(self)
    let parsed = parse_at_least_args(arg, 2, "argument format error, need format is to_address,integer_amount[,memo]")
    let info = {to: parsed[1], amount: tointeger(parsed[2])}
    let to = tostring(info.to)
    let amount = tointeger(info.amount)
    if (not to) or (#to < 1) then
        return error("to address format error")
    end
    if (not amount) or (amount < 1) then
        return error("amount format error")
    end
    checkAddress(to)
    let users = self.storage.users
    if (not users[caller_address]) or (users[caller_address] < amount) then
        return error("you have not enoungh amount to transfer out")
    end
    users[caller_address] = tointeger(users[caller_address] or 0) - amount
    if users[caller_address] == 0 then
        users[caller_address] = nil
    end
    users[to] = tointeger(users[to] or 0) + amount
    self.storage.users = users
    let eventArgStr = json.dumps({from: caller_address, to: to, amount: amount})
    emit Transfer(eventArgStr)
end

-- arg: to_address,integer_amount
function M:issue(arg: string)
    checkAdmin(self)
    checkState(self)
    let parsed = parse_args(arg, 2, "argument format error, need format is to_address,integer_amount}")
    let info = {to: parsed[1], amount: tointeger(parsed[2])}
    let to = tostring(info.to)
    let amount = tointeger(info.amount)
    if (not to) or (#to < 1) then
        return error("to address format error")
    end
    if (not amount) or (amount < 1) then
        return error("amount format error")
    end
    checkAddress(to)
    
    let users = self.storage.users
    let balanceOld = tointeger(users[to] or 0)
    let balance = balanceOld + amount
    if (balance < balanceOld) or (balance < amount) or (balance < 0) then
        return error("balance overflow")
    end
    users[to] = balance
    self.storage.users = users
    
    let supplyOld = self.storage.supply
    let supply = supplyOld + amount
    if (supply < supplyOld) or (supply < amount) or (supply < 0) then
        return error("supply overflow")
    end 
    self.storage.supply = supply
    
    let eventArgStr = json.dumps({from: caller_address, to: to, amount: amount})
    emit Issued(eventArgStr)
end

-- arg format: fromAddress,toAddress,amount(with precision)
function M:transferFrom(arg: string)
    checkState(self)
    let parsed = parse_at_least_args(arg, 3, "argument format error, need format is fromAddress,toAddress,amount(with precision)")
    let fromAddress = tostring(parsed[1])
    let toAddress = tostring(parsed[2])
    let amount = tointeger(parsed[3])
    checkAddress(fromAddress)
    checkAddress(toAddress)
    if (not amount) or (amount < 0) then
        return error("amount must be positive integer")
    end
    let allowed = self.storage.allowed
    let users = self.storage.users
    if (not users[fromAddress]) or (amount > users[fromAddress]) then
        return error("fromAddress not have enough token to withdraw")
    end
    let allowedDataStr = allowed[fromAddress]
    if (not allowedDataStr) then
        return error("not enough approved amount to withdraw")
    end
    let allowedData: Map<int> = totable(json.loads(allowedDataStr))
    if (not allowedData) or (not allowedData[caller_address]) then
        return error("not enough approved amount to withdraw")
    end
    let approvedAmount = tointeger(allowedData[caller_address])
    if (not approvedAmount) or (amount > approvedAmount) then
        return error("not enough approved amount to withdraw")
    end
    users[toAddress] = tointeger(users[toAddress] or 0) + amount
    users[fromAddress] = users[fromAddress] - amount
    if users[fromAddress] == 0 then
        users[fromAddress] = nil
    end
    allowedData[caller_address] = approvedAmount - amount
    if allowedData[caller_address] == 0 then
        allowedData[caller_address] = nil
    end
    allowed[fromAddress] = json.dumps(allowedData)
    self.storage.users = users
    self.storage.allowed = allowed
    let eventArgStr = json.dumps({from: fromAddress, to: toAddress, amount: amount})
    emit Transfer(eventArgStr)
end

-- arg format: spenderAddress,amount(with precision)
function M:approve(arg: string)
    checkState(self)
    let allowed = self.storage.allowed
    let parsed = parse_at_least_args(arg, 2, "argument format error, need format is spenderAddress,amount(with precision)")
    let spender = tostring(parsed[1])
    checkAddress(spender)
    let amount = tointeger(parsed[2])
    if (not amount) or (amount < 0) then
        return error("amount must be non-negative integer")
    end
    var allowedData: Map<int>
    if (not allowed[caller_address]) then
        allowedData = {}
    else
        allowedData = totable(json.loads(allowed[caller_address]))
        if not allowedData then
            return error("allowed storage data error")
        end
    end
    allowedData[spender] = amount
    allowed[caller_address] = json.dumps(allowedData)
    self.storage.allowed = allowed
    let eventArg = {from: caller_address, spender: spender, amount: amount}
    emit Approved(json.dumps(eventArg))
end

-- arg format: spenderAddress,authorizerAddress
offline function M:approvedBalanceFrom(arg: string)
    let allowed = self.storage.allowed
    let parsed = parse_at_least_args(arg, 2, "argument format error, need format is spenderAddress,authorizerAddress")
    let spender = tostring(parsed[1])
    let authorizer = tostring(parsed[2])
    checkAddress(spender)
    checkAddress(authorizer)
    let allowedDataStr = allowed[authorizer]
    if (not allowedDataStr) then
        return "0"
    end
    let allowedData: Map<int> = totable(json.loads(allowedDataStr))
    if (not allowedData) then
        return "0"
    end
    let allowedAmount = allowedData[spender]
    if (not allowedAmount) then
        return "0"
    end
    let allowedAmountStr = tostring(allowedAmount)
    return allowedAmountStr
end

-- arg format: fromAddress
offline function M:allApprovedFromUser(arg: string)
    let allowed = self.storage.allowed
    let authorizer = arg
    checkAddress(authorizer)
    let allowedDataStr = allowed[authorizer]
    if (not allowedDataStr) then
        return "{}"
    end
    return allowedDataStr
end

function M:pause(arg: string)
    if self.storage.state == 'STOPPED' then
        return error("this contract stopped now, can't pause")
    end
    if self.storage.state == 'PAUSED' then
        return error("this contract paused now, can't pause")
    end
    checkAdmin(self)
    self.storage.state = 'PAUSED'
    emit Paused("")
end

function M:resume(arg: string)
    if self.storage.state ~= 'PAUSED' then
        return error("this contract not paused now, can't resume")
    end
    checkAdmin(self)
    self.storage.state = 'COMMON'
    emit Resumed("")
end

function M:stop(arg: string)
    if self.storage.state == 'STOPPED' then
        return error("this contract stopped now, can't stop")
    end
    if self.storage.state == 'PAUSED' then
        return error("this contract paused now, can't stop")
    end
    checkAdmin(self)
    self.storage.state = 'STOPPED'
    emit Stopped("")
end

-- arg: integer_amount,unlockBlockNumber
function M:lock(arg: string)
    checkState(self)
    if (not self.storage.allowLock) then
        return error("this token contract not allow lock balance")
    end
    let parsed = parse_args(arg, 2, "arg format error, need format is integer_amount,unlockBlockNumber")
    let toLockAmount = tointeger(parsed[1])
    let unlockBlockNumber = tointeger(parsed[2])
    if (not toLockAmount) or (toLockAmount<1) then
        return error("to unlock amount must be positive integer")
    end
    if (not unlockBlockNumber) or (unlockBlockNumber < get_header_block_num()) then
        return error("to unlock block number can't be earlier than current block number " .. tostring(get_header_block_num()))
    end
    let balance = getBalanceOfUser(self, caller_address)
    if (toLockAmount > balance) then
        return error("you have not enough balance to lock")
    end
    let lockedAmounts = self.storage.lockedAmounts
    if (not lockedAmounts[caller_address]) then
        lockedAmounts[caller_address] = tostring(toLockAmount) .. ',' .. tostring(unlockBlockNumber)
    else
        return error("you have locked balance now, before lock again, you need unlock them or use other address to lock")
    end
    self.storage.lockedAmounts = lockedAmounts
    self.storage.users[caller_address] = balance - toLockAmount
    emit Locked(tostring(toLockAmount))
end

function M:unlock(_: string)
    checkState(self)
    if (not self.storage.allowLock) then
        return error("this token contract not allow lock balance")
    end
    
    let lockedAmounts = self.storage.lockedAmounts
    if (not lockedAmounts[caller_address]) then
        return error("you have not locked balance")
    end
    let lockedInfoParsed = parse_args(lockedAmounts[caller_address], 2, "locked amount info format error")
    let lockedAmount = tointeger(lockedInfoParsed[1])
    let canUnlockBlockNumber = tointeger(lockedInfoParsed[2])

    if (get_header_block_num() < canUnlockBlockNumber) then
        return error("your locked balance only can be unlock after block #" .. tostring(canUnlockBlockNumber))
    end
    lockedAmounts[caller_address] = nil
    self.storage.lockedAmounts = lockedAmounts
    self.storage.users[caller_address] = getBalanceOfUser(self, caller_address) + lockedAmount
    emit Unlocked(caller_address .. ',' .. tostring(lockedAmount))
end

-- arg: userAddress
-- only admin can call this api
function M:forceUnlock(arg: string)
    checkState(self)
    if (not self.storage.allowLock) then
        return error("this token contract not allow lock balance")
    end
    checkAdmin(self)
    let userAddr = arg
    if (not userAddr) or (#userAddr < 1) then
        return error("argument format error, need format userAddress")
    end
    checkAddress(userAddr)

    let lockedAmounts = self.storage.lockedAmounts
    if (not lockedAmounts[userAddr]) then
        return error("this user have not locked balance")
    end
    let lockedInfoParsed = parse_args(lockedAmounts[userAddr], 2, "locked amount info format error")
    let lockedAmount = tointeger(lockedInfoParsed[1])
    let canUnlockBlockNumber = tointeger(lockedInfoParsed[2])

    if (get_header_block_num() < canUnlockBlockNumber) then
        return error("this user locked balance only can be unlock after block #" .. tostring(canUnlockBlockNumber))
    end
    lockedAmounts[userAddr] = nil
    self.storage.lockedAmounts = lockedAmounts
    self.storage.users[userAddr] = getBalanceOfUser(self, userAddr) + lockedAmount
    emit Unlocked(userAddr .. ',' .. tostring(lockedAmount))
end

offline function M:lockedBalanceOf(owner: string)
    let lockedAmounts = self.storage.lockedAmounts
    if (not lockedAmounts[owner]) then
        return '0,0'
    else
        let resultStr = lockedAmounts[owner]
        return resultStr
    end
end

function M:on_destroy()
    error("can't destroy token contract")
end

return M
