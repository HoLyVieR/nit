module test

import orm

class DecoratedIntTranslator
    super OrmTranslator[Int]

    redef fun from_db(o) do
        assert o isa String
        o = o.substring(2, o.length - 4)
        return o.to_n.as(Int)
    end

    redef fun to_db(o) do
        return "--" + o.to_s + "--"
    end
end

class MyTestClass
    table
    named "MyDBTable"

    var field1 : Int = 0 is primary, field, named "id"
    var field2 : Int = 0 is field, translated_by "DecoratedIntTranslator"
end

var entry = with_db("test.sqlite3").
    select.
    from("MyTestClass").
    where("id = ?", [800]).
    first.
    as(MyTestClass)

print("Entry with ID = 800")
print("---")
print("Value Field 1 : " + entry.field1.to_s)
print("Value Field 2 : " + entry.field2.to_s)
print("---")

var query = with_db("test.sqlite3").
    select.
    from("MyTestClass")

print("")
print("All entries")
print("---")

for v in query do
    v = v.as(MyTestClass)
    print("Value Field 1 : " + v.field1.to_s)
    print("Value Field 2 : " + v.field2.to_s)
    print("---")
end

# entry.field2 = 888
# entry.save

# var new_entry = new MyTestClass
# new_entry.field1 = 111
# new_entry.field2 = 333
# with_db("test.sqlite3").
#     insert.
#     into("MyTestClass").
#     value(new_entry).
#     execute
