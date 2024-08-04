document.addEventListener("DOMContentLoaded", () => {
    console.log("Document is ready");

    function addShift(shiftType) {
        const name = prompt("Enter the name for the " + shiftType + " shift:");
        if (name) {
            const li = document.createElement('li');
            li.textContent = name;
            li.appendChild(createDeleteButton());
            document.getElementById(shiftType + '-shift-list').appendChild(li);
        }
    }

    function addOfficeDay() {
        const name = prompt("Enter the name for the office day:");
        if (name) {
            const li = document.createElement('li');
            li.textContent = name;
            li.appendChild(createDeleteButton());
            document.getElementById('office-days-list').appendChild(li);
        }
    }

    function addMeeting() {
        const name = prompt("Enter the meeting details:");
        if (name) {
            const li = document.createElement('li');
            li.textContent = name;
            li.appendChild(createDeleteButton());
            document.getElementById('meetings-list').appendChild(li);
        }
    }

    function createDeleteButton() {
        const button = document.createElement('button');
        button.textContent = 'Delete';
        button.classList.add('delete');
        button.style.marginLeft = '10px';
        button.onclick = function() {
            const li = this.parentElement;
            li.parentElement.removeChild(li);
        };
        return button;
    }

    // Attach functions to the window object
    window.addShift = addShift;
    window.addOfficeDay = addOfficeDay;
    window.addMeeting = addMeeting;

    document.getElementById('publish-btn').addEventListener('click', function() {
        const { jsPDF } = window.jspdf;
        const doc = new jsPDF();

        // Add title and date
        doc.text('196ATKS Schedule', 10, 10);
        doc.text('Date: ' + document.getElementById('date-input').value, 10, 20);

        // Add content from different sections
        const dayShiftList = document.getElementById('day-shift-list').innerText;
        const swingShiftList = document.getElementById('swing-shift-list').innerText;
        const midsShiftList = document.getElementById('mids-shift-list').innerText;
        const officeDaysList = document.getElementById('office-days-list').innerText;
        const meetingsList = document.getElementById('meetings-list').innerText;

        doc.text('Day Shift:', 10, 30);
        doc.text(dayShiftList, 10, 40);

        doc.text('Swing Shift:', 10, 50);
        doc.text(swingShiftList, 10, 60);

        doc.text('Mids Shift:', 10, 70);
        doc.text(midsShiftList, 10, 80);

        doc.text('Office Days:', 10, 90);
        doc.text(officeDaysList, 10, 100);

        doc.text('Meetings:', 10, 110);
        doc.text(meetingsList, 10, 120);

        // Save the PDF
        doc.save('schedule.pdf');
    });


    // Handle dynamic date
    const dateInput = document.getElementById('date-input');
    dateInput.addEventListener('change', () => {
        document.querySelector('h1').textContent = `196ATKS schedule for ${dateInput.value}`;
    });
});

