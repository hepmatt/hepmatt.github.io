<?php
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Collect form data
    $firstName = $_POST['first-name'];
    $lastName = $_POST['last-name'];
    $email = $_POST['email'];
    $phone = $_POST['phone'];
    $address = $_POST['address'];
    $city = $_POST['city'];
    $state = $_POST['state'];
    $zip = $_POST['zip'];
    $country = $_POST['country'];
    $visitReason = $_POST['visit-reason'];
    $comments = $_POST['comments'];

    // Recipient email
    $to = 'contactme@mattlynn.com';

    // Email subject
    $subject = 'New Visitor Data Card Submission';

    // Email body
    $message = "First Name: $firstName\n";
    $message .= "Last Name: $lastName\n";
    $message .= "Email: $email\n";
    $message .= "Phone: $phone\n";
    $message .= "Address: $address\n";
    $message .= "City: $city\n";
    $message .= "State/Province: $state\n";
    $message .= "ZIP/Postal Code: $zip\n";
    $message .= "Country: $country\n";
    $message .= "Reason for Visit: $visitReason\n";
    $message .= "Comments: $comments\n";

    // Email headers
    $headers = "From: $email\r\n";
    $headers .= "Reply-To: $email\r\n";

    // Send email
    if (mail($to, $subject, $message, $headers)) {
        echo 'Your data has been sent successfully!';
    } else {
        echo 'Failed to send your data. Please try again.';
    }
}
?>
