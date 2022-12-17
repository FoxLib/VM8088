<?php

$replace = ['core_alu', 'core_decl', 'core_exec', 'core_proc'];

if (file_exists("core_top.v")) {

    $core = file_get_contents("core_top.v");
    foreach ($replace as $name) {

        if (preg_match('~([ ]*)`include "(.+)"~m', $core, $c)) {

            $size = strlen($c[1]);
            $file = file($c[2]);
            foreach ($file as $i => $v) $file[$i] = $c[1] . rtrim($v);
            $file = join("\n", $file);
            $core = str_replace($c[0], $file, $core);
        }
    }

    $core = preg_replace('~\s+$~m', '', $core);
    file_put_contents("../core.v", $core);
}
