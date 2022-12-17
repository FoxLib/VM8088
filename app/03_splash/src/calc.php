<?php

$im = imagecreatefrompng("image.png");

[$w, $h] = [imagesx($im), imagesy($im)];

$palette = [];
$allidx = [];
$image = [];

$stream = [];
$stream_id = 0;

function putbit($bit) {

    global $stream, $stream_id;

    $n = $stream_id >> 3;
    $k = $stream_id & 7;

    if (!isset($stream[$n])) $stream[$n] = 0;
    if ($bit) $stream[$n] |= (1 << $k);

    $stream_id++;
}

function putnum($v, $cnt) {

    for ($i = 0; $i < $cnt; $i++) {
        putbit($v & (1 << $i));
    }
}

// -----------------------------------------------------------------------------

// Прочитать все возможные цвета палитры
for ($i = 0; $i < imagecolorstotal($im); $i++) {

    $cl  = imagecolorsforindex($im, $i);
    $palette[$i] = $cl;
}

// Сканирование количества цветов
for ($y = 0; $y < $h; $y++)
for ($x = 0; $x < $w; $x++) {

    $idx = imagecolorat($im, $x, $y);
    if (empty($allidx[$idx])) $allidx[$idx] = 0;
    $allidx[$idx]++;

    $image[$x + $y*$w] = $idx;
}

// -----------------------------------------------------------------------------

// Вычисление нужного количества битов для хранения цвета
$cnt    = count($allidx);
$bitcnt = log($cnt) / log(2);
if (floor($bitcnt) < $bitcnt) $bitcnt = floor($bitcnt) + 1;

putnum($bitcnt, 4); // Количество битов
putnum($w, 8);      // Ширина и высота
putnum($h, 8);      // Ширина и высота


// Выгрузка палитры 4x4x4
for ($i = 0; $i < $cnt; $i++) {

    $cl = $palette[$i];
    putnum($cl['red']   >> 4, 4);
    putnum($cl['green'] >> 4, 4);
    putnum($cl['blue']  >> 4, 4);
}

// Цветовые данные
foreach ($image as $v) putnum($v, $bitcnt);

print_r(array_map('dechex', $stream));
