<?php

$bin  = file_get_contents($argv[1]);
$out  = [];
$size = strlen($bin);

for ($i = 0; $i < $size; $i++) $out[] = sprintf("%02X", ord($bin[$i]));

file_put_contents($argv[2], join("\n", $out));