
void main(List<String> args) {
  String local1 = 'abc';
  int local2 = 2;

  print('hello from main');

  foo(1);
  foo(2);
  foo(3);

  print('exiting...');
}

void foo(int val) {
  print('val: ${val}');
}
