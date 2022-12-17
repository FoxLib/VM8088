<?php

/*
 * Конвертирование из Bin -> MIF файл
 * Аргумент 1: bin-файл
 * Аргумент 2: Размер памяти (256k = 262144)
 */

$data = file_get_contents($argv[1]);
$size = (int) @ $argv[2];
if ($size < 1024) $size *= 1024;
$len  = strlen($data);

if (empty($size)) { echo "size required\n"; exit(1); }

?>
WIDTH=8;
DEPTH=<?=$size;?>;
ADDRESS_RADIX=HEX;
DATA_RADIX=HEX;
CONTENT BEGIN
<?php

$a = 0;

// RLE-кодирование
while ($a < $len) {

    // Поиск однотонных блоков
    for ($b = $a + 1; $b < $len && $data[$a] == $data[$b]; $b++);

    // Если найденный блок длиной до 0 до 2 одинаковых символов
    if ($b - $a < 3) {
        for ($i = $a; $i < $b; $i++) echo sprintf("  %x: %02x;\n", $a++, ord($data[$i]));
    } else {
        echo sprintf("  [%x..%x]: %02x;\n", $a, $b-1, ord($data[$a]));
        $a = $b;
    }
}
if ($len < $size) echo sprintf("  [%x..%x]: 00;\n", $len, $size-1);
?>
END;

