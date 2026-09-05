fn promoted<const N: i32>() -> i32 {
    let values = &[N; 4];
    values[0]
}

fn main() {
    assert_eq!(promoted::<7>(), 7);
}
