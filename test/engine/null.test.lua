env = require('test_run')
test_run = env.new()
engine = test_run:get_cfg('engine')
msgpack = require('msgpack')

--
-- gh-1557: box.NULL in indexes.
--


box.NULL == msgpack.NULL
box.NULL == nil

msgpack.decode(msgpack.encode({box.NULL}))

format = {}
format[1] = { name = 'field1', type = 'unsigned' }
format[2] = { name = 'field2', type = 'unsigned', is_nullable = true }
s = box.schema.space.create('test', { engine = engine, format = format })

-- Bad nullable value.
format[2].is_nullable = 100
s:format(format) -- Fail.

-- Primary can not be nullable.
parts = {}
parts[1] = {field = 2, type = 'unsigned', is_nullable = true}
pk = s:create_index('pk', { parts = parts }) -- Fail.

pk = s:create_index('pk')

-- Not TREE nullable.
-- Do not print errmsg, because Vinyl's one is different - it does
-- not support HASH.
ok = pcall(s.create_index, s, 'sk', { parts = parts, type = 'hash' }) -- Fail.
ok

-- Conflict of is_nullable in format and in parts.
parts[1].is_nullable = false
sk = s:create_index('sk', { parts = parts }) -- Fail.

-- Try skip nullable in format and specify in part.
parts[1].is_nullable = true
sk = s:create_index('sk', { parts = parts }) -- Ok.
format[2].is_nullable = nil
s:format(format) -- Fail.
sk:drop()

-- Try to set nullable in part with no format.
s:format({})
sk = s:create_index('sk', { parts = parts })
-- And then set format with no nullable.
s:format(format) -- Fail.
format[2].is_nullable = true
s:format(format) -- Ok.

-- Test insert.

s:insert{1, 1}
s:insert{2, box.NULL}
s:insert{3, box.NULL}
s:insert{4, 1} -- Fail.
s:insert{4, 4}
s:insert{5, box.NULL}

pk:select{}
sk:select{}

-- Test exact match.

sk:get({1})
sk:get({box.NULL}) -- Fail.

sk:update({1}, {})
sk:update({box.NULL}, {}) -- Fail.

_ = sk:delete({1})
sk:delete({box.NULL}) -- Fail.
s:insert({1, 1})

-- Test iterators.

sk:select{box.NULL}
sk:select({box.NULL}, {iterator = 'LE'})
sk:select({box.NULL}, {iterator = 'LT'})
sk:select({box.NULL}, {iterator = 'GE'})
sk:select({box.NULL}, {iterator = 'GT'})

_ = sk:delete{box.NULL}
sk:select{}
pk:select{}

-- Test snapshot during iterator (Vinyl restore).

create_iterator = require('utils').create_iterator

iter = create_iterator(sk, {box.NULL})
iter.next()

box.snapshot()
iter.iterate_over()

sk:select{}
pk:select{}

-- Test replace.

s:replace{2, 2}
s:replace{3, box.NULL} -- no changes.
s:replace{6, box.NULL}

pk:select{}
sk:select{}

-- Test not unique indexes.

s:truncate()
sk:drop()
sk = s:create_index('sk', { parts = parts, unique = false })

s:insert{1, 1}
s:insert{2, box.NULL}
s:insert{3, box.NULL}
s:insert{4, 1}
s:insert{5, box.NULL}

pk:select{}
sk:select{}

-- Test several secondary indexes.

s:truncate()
format[2].is_nullable = true
format[3] = { name = 'field3', type = 'unsigned', is_nullable = true }
s:format(format)
parts[1].field = 3
sk2 = s:create_index('sk2', { parts = parts })

s:replace{4, 3, 4}
s:replace{3, 3, 3}
s:replace{2, box.NULL, box.NULL}
s:replace{1, box.NULL, 1}
s:replace{0, 0, box.NULL}

pk:select{}
sk:select{}
sk2:select{}

-- Check duplicate conflict on replace.

s:replace{4, 4, 3} -- fail
s:replace{4, 4, box.NULL} -- ok

pk:select{}
sk:select{}
sk2:select{}

_ = pk:delete{2}
pk:select{}
sk:select{}
sk2:select{}

s:drop()

--
-- gh-2880: allow to store less field count than specified in a
-- format.
--
format = {}
format[1] = {name = 'field1', type = 'unsigned'}
format[2] = {name = 'field2', type = 'unsigned'}
format[3] = {name = 'field3'}
format[4] = {name = 'field4', is_nullable = true}
s = box.schema.create_space('test', {engine = engine, format = format})
pk = s:create_index('pk')
sk = s:create_index('sk', {parts = {2, 'unsigned'}})

s:replace{1, 2} -- error
t1 = s:replace{2, 3, 4}
t2 = s:replace{3, 4, 5, 6}
t1.field1, t1.field2, t1.field3, t1.field4
t2.field1, t2.field2, t2.field3, t2.field4
 -- Ensure the tuple is read ok from disk in a case of vinyl.
if engine == 'vinyl' then box.snapshot() end
s:select{2}

s:drop()

-- Check the case when not contiguous format tail is nullable.
format = {}
format[1] = {name = 'field1', type = 'unsigned'}
format[2] = {name = 'field2', type = 'unsigned'}
format[3] = {name = 'field3'}
format[4] = {name = 'field4', is_nullable = true}
format[5] = {name = 'field5'}
format[6] = {name = 'field6', is_nullable = true}
format[7] = {name = 'field7', is_nullable = true}
s = box.schema.create_space('test', {engine = engine, format = format})
pk = s:create_index('pk')
sk = s:create_index('sk', {parts = {2, 'unsigned'}})

s:replace{1, 2} -- error
s:replace{2, 3, 4} -- error
s:replace{3, 4, 5, 6} -- error
t1 = s:replace{4, 5, 6, 7, 8}
t2 = s:replace{5, 6, 7, 8, 9, 10}
t3 = s:replace{6, 7, 8, 9, 10, 11, 12}
t1.field1, t1.field2, t1.field3, t1.field4, t1.field5, t1.field6, t1.field7
t2.field1, t2.field2, t2.field3, t2.field4, t2.field5, t2.field6, t2.field7
t3.field1, t3.field2, t3.field3, t3.field4, t3.field5, t3.field6, t3.field7
s:select{}

s:drop()

-- Check nullable indexes with other types
s = box.schema.space.create('test', {engine = engine})
_ = s:create_index('pk')
_ = s:create_index('i1', {parts = {{2, 'string', is_nullable = true}}})
_ = s:create_index('i2', {parts = {{3, 'number', is_nullable = true}}})
_ = s:create_index('i3', {parts = {{4, 'integer', is_nullable = true}}})
_ = s:create_index('i4', {parts = {{5, 'boolean', is_nullable = true}}, unique = false})
_ = s:create_index('i5', {parts = {{6, 'scalar', is_nullable = true}}})

_ = s:auto_increment{box.NULL, 1.11, -111, false, '111'}
_ = s:auto_increment{'222', box.NULL, -222, true, 222}
_ = s:auto_increment{'333', 3.33, box.NULL, false, 3.33}
_ = s:auto_increment{'444', 4.44, -444, box.NULL, true}
_ = s:auto_increment{'555', 5.55, -555, false, box.NULL}

box.snapshot()

_ = s:auto_increment{box.NULL, 6.66, -666, true, '666'}
_ = s:auto_increment{'777', box.NULL, -777, false, 777}
_ = s:auto_increment{'888', 8.88, box.NULL, true, 8.88}
_ = s:auto_increment{'999', 9.99, -999, box.NULL, false}
_ = s:auto_increment{'000', 0.00, -000, true, box.NULL}

s.index.i1:select()
s.index.i2:select()
s.index.i3:select()
s.index.i4:select()
s.index.i5:select()

s:drop()
