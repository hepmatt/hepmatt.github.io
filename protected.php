<?php
$correctPassword = 'password';

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $password = $_POST['password'];

    if ($password == $correctPassword) {
        echo '<p>Access granted. <a href="display.html">Go to Protected Page</a></p>';
    } else {
        echo '<p>Incorrect password. <a href="index.html">Try again</a></p>';
    }
} else {
    header('Location: index.html');
    exit();
}
?>
