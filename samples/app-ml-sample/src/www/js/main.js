$( document ).ready(function() {
    $("#solve").click(function(){
        var rn = $("#rn").val();
        var delta = $("#delta").val();
        var data = {"rn": rn, "delta": delta};
        console.log("to solve: " + JSON.stringify(data))
        if (isNumeric(rn) && isNumeric(delta) && rn >= 0 && delta >= 0) {
            this.disabled = true;
            $.post("./ui/solve", JSON.stringify(data))
            .done(() => {
                $("#output").html("Solving:");
                pollingRe($("#output"));
            })
            .always(() => {
                this.disabled = false;
            });
        } else {
            $("#output").val("Invalid input for solver!");
        }
    });
});

function isNumeric(n) {
    return !isNaN(parseFloat(n)) && isFinite(n);
};

function pollingRe(output) {
    setTimeout(() => {
        $.get("./ui/solve", (data) => {
            console.log("GET /ui/solve:" + data);
            let arr = JSON.parse(data);
            if (arr.length !== 0 && arr[0] === "over") {
                return;
            } else {
                var new_output = output.html() + ' ' + arr.join(' ');
                output.html(new_output);
                pollingRe(output);
            }
        });
    }, 1000);
};