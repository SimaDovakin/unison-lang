
```unison
test1_term = '(printLine "Hello")
```

```ucm:hide
.> add
```

```unison
test1 = '(runInScheme 1 (termLink test1_term))
```

```ucm
.> run test1
```