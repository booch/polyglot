actor Main
    let x: U64 = 1
    var _name: String = "world"

    new create(env: Env) =>
        let z: U64 = x + 1
        _name = "Craig"
        env.out.print("Hello, " + name() + "!")

    fun name(): String =>
        _name
