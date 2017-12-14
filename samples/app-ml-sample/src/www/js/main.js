$( document ).ready(function() {
    $("#solve").click(function(){
        var rn = $("#rn").val();
        var delta = $("#delta").val();
        if (isNumeric(rn) && isNumeric(delta) && rn >= 0 && delta >= 0) {
            this.disabled = true;
            $.post("./ui/solve",$( "#solver" ).serialize())
            .done(() => {
                $("#output").val("Solving:");
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
        $.get("/ui/solve", (data) => {
            if (data.length !== 0 && data[0] === "over") {
                return;
            } else {
                var new_output = output.val() + ' ' + data.join(' ');
                output.val(new_output);
                pollingRe(output);
            }
        });
    }, 1000);
};