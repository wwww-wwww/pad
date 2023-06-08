defmodule Pad.Paginator do
  use Agent
  alias Nostrum.Api
  alias Nostrum.Struct.Interaction

  defstruct embeds: [], time: nil, interaction: nil

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_components(pages, current_page) do
    if length(pages) <= 5 do
      1..length(pages)
      |> Enum.map(
        &%{
          type: 2,
          label: "#{&1}",
          style: 1,
          custom_id: "page:#{&1 - 1}",
          disabled: current_page == &1 - 1
        }
      )
    else
      [
        %{
          type: 2,
          label: "❙❮",
          style: 1,
          custom_id: "page_jump:0",
          disabled: current_page == 0
        },
        %{
          type: 2,
          label: "❮",
          style: 1,
          custom_id: "page:#{current_page - 1}",
          disabled: current_page == 0
        },
        %{
          type: 2,
          label: "❯",
          style: 1,
          custom_id: "page:#{current_page + 1}",
          disabled: current_page == length(pages) - 1
        },
        %{
          type: 2,
          label: "❯❙",
          style: 1,
          custom_id: "page_jump:#{length(pages) - 1}",
          disabled: current_page == length(pages) - 1
        }
      ]
    end
  end

  def create(pages, %Interaction{id: id} = interaction) do
    data =
      if length(pages) == 1 do
        %{embeds: Enum.take(pages, 1)}
      else
        Agent.update(
          __MODULE__,
          &Map.put(&1, id, %__MODULE__{embeds: pages, interaction: interaction})
        )

        %{
          embeds: [Enum.at(pages, 0)],
          components: [
            %{
              type: 1,
              components: get_components(pages, 0)
            }
          ]
        }
      end

    Api.create_interaction_response(interaction, %{
      type: 4,
      data: data
    })
  end

  def change_page(interaction, id, new_page) do
    {new_page, _} = Integer.parse(new_page)

    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil ->
        nil

      %{embeds: pages} ->
        Api.create_interaction_response(interaction, %{
          type: 7,
          data: %{
            embeds: [Enum.at(pages, new_page)],
            components: [
              %{
                type: 1,
                components: get_components(pages, new_page)
              }
            ]
          }
        })
    end
  end
end
