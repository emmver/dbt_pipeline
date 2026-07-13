{% test date_parseable(model, column_name) %}
select *
from {{ model }}
where coalesce(
    try_cast({{ column_name }} as date),
    try_strptime({{ column_name }}, '%d/%m/%Y')::date,
    try_strptime({{ column_name }}, '%d-%b-%y')::date
) is null
{% endtest %}