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

   

    // Handle dynamic date
    const dateInput = document.getElementById('date-input');
    dateInput.addEventListener('change', () => {
        document.querySelector('h1').textContent = `196ATKS schedule for ${dateInput.value}`;
    });
});

