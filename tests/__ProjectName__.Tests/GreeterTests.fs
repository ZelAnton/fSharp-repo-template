namespace __ProjectName__.Tests

open NUnit.Framework
open __ProjectName__

[<TestFixture>]
type GreeterTests() =

    [<Test>]
    member _.``greet returns greeting with name``() =
        Assert.That(Greeter.greet "World", Is.EqualTo "Hello, World!")
